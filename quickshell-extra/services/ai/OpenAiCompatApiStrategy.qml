import QtQuick

/**
 * Strategy for generic OpenAI-compatible chat APIs (Groq, NVIDIA NIM, OpenRouter, Cerebras, ...)
 * Use with `"api_format": "openai_compat"` on a model.
 *
 * Differences from OpenAiApiStrategy:
 * - Tool calls work: streamed tool-call fragments are accumulated, the assistant's
 *   `tool_calls` are echoed back, and function outputs are sent as `tool` messages
 *   with the matching `tool_call_id` (strict providers reject anything else).
 * - The tool call is handed to Ai.qml only after the stream ends (onRequestFinished),
 *   so the follow-up request never races the still-running curl process.
 * - An empty `tools` array is omitted (some providers reject `"tools": []`).
 * - Provider error formats ({error:{...}}, {detail/title}) are shown readably.
 */
ApiStrategy {
    property bool isReasoning: false
    property var pendingToolCalls: ({}) // index -> { id, name, arguments }
    property bool sawToolCalls: false

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function stripForHistory(text) {
        // Drop the UI-only function marker / command-request blocks and reasoning
        let t = text ?? "";
        const markerIdx = t.indexOf("\n\n[[ Function: ");
        if (markerIdx >= 0) t = t.slice(0, markerIdx);
        t = t.replace(/<think>[\s\S]*?<\/think>/g, "");
        return t.trim();
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        const out = [{ role: "system", content: systemPrompt }];
        let openCallIds = []; // tool_call ids still waiting for a tool response

        const closeOpenCalls = () => {
            // Every tool_call must be answered before the conversation can continue
            openCallIds.forEach(id => out.push({
                role: "tool", tool_call_id: id,
                content: "No result: the user continued the conversation without running this.",
            }));
            openCallIds = [];
        };

        messages.forEach(message => {
            const call = message.functionCall;
            const isFunctionOutput = message.role === "user"
                && (message.functionName?.length ?? 0) > 0
                && !call;

            if (isFunctionOutput) {
                if (openCallIds.length > 0) {
                    out.push({
                        role: "tool",
                        tool_call_id: openCallIds.shift(),
                        content: message.functionResponse?.length > 0 ? message.functionResponse : "(no output)",
                    });
                } else {
                    // Orphan output (e.g. chat made with another model): send as plain text
                    out.push({ role: "user", content: `Output of ${message.functionName}:\n${message.functionResponse}` });
                }
                return;
            }

            closeOpenCalls();

            if (message.role === "assistant" && call && call.name) {
                const id = call.id || `call_${Math.random().toString(36).slice(2, 10)}`;
                const text = stripForHistory(message.rawContent);
                out.push({
                    role: "assistant",
                    content: text.length > 0 ? text : null,
                    tool_calls: [{
                        id: id, type: "function",
                        function: { name: call.name, arguments: JSON.stringify(call.args ?? {}) },
                    }],
                });
                openCallIds.push(id);
                return;
            }

            out.push({
                role: message.role,
                content: message.role === "assistant" ? stripForHistory(message.rawContent) : message.rawContent,
            });
        });
        closeOpenCalls();

        let baseData = {
            "model": model.model,
            "messages": out,
            "stream": true,
            "temperature": temperature,
        };
        if (tools && tools.length > 0) baseData.tools = tools;
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function appendText(message, text) {
        message.rawContent += text;
        message.content += text;
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) cleanData = cleanData.slice(5).trim();

        if (!cleanData || cleanData.startsWith(":") || cleanData.startsWith("event:")) return {};
        if (cleanData === "[DONE]") return {}; // Finish is handled on process exit

        let dataJson;
        try {
            dataJson = JSON.parse(cleanData);
        } catch (e) {
            // Non-JSON line (plain-text error, HTML, multi-line JSON): show as-is
            appendText(message, line + "\n");
            return {};
        }

        // Error formats: OpenAI/Groq {error:{message}}, NIM/FastAPI {detail} or {title, detail}
        const err = dataJson.error ?? (dataJson.choices === undefined ? (dataJson.detail ?? dataJson.title) : undefined);
        if (err !== undefined) {
            const errText = typeof err === "string" ? err : (err.message ?? JSON.stringify(err));
            appendText(message, `**Error**: ${errText}`);
            if (/api.?key|unauthori[sz]ed|401|403|forbidden/i.test(errText + (dataJson.status ?? ""))) {
                appendText(message, "\n\nSet your key for this provider with `/key YOUR_API_KEY`.");
            }
            return { finished: true };
        }

        const choice = dataJson.choices?.[0];
        const delta = choice?.delta ?? choice?.message ?? {};

        // Tool calls arrive in fragments keyed by index
        if (delta.tool_calls) {
            sawToolCalls = true;
            delta.tool_calls.forEach(tc => {
                const idx = tc.index ?? 0;
                const cur = pendingToolCalls[idx] ?? { id: "", name: "", arguments: "" };
                if (tc.id) cur.id = tc.id;
                if (tc.function?.name) cur.name += tc.function.name;
                if (tc.function?.arguments) cur.arguments += tc.function.arguments;
                pendingToolCalls[idx] = cur;
            });
        }

        const content = delta.content;
        const reasoning = delta.reasoning ?? delta.reasoning_content;
        if (content && content.length > 0) {
            if (isReasoning) {
                isReasoning = false;
                appendText(message, "\n\n</think>\n\n");
            }
            appendText(message, content);
        } else if (reasoning && reasoning.length > 0) {
            if (!isReasoning) {
                isReasoning = true;
                appendText(message, "\n\n<think>\n\n");
            }
            appendText(message, reasoning);
        }

        // Usage: standard `usage`, or Groq's `x_groq.usage` on the last chunk
        const usage = dataJson.usage ?? dataJson.x_groq?.usage;
        if (usage) {
            return { tokenUsage: {
                input: usage.prompt_tokens ?? -1,
                output: usage.completion_tokens ?? -1,
                total: usage.total_tokens ?? -1,
            } };
        }
        return {};
    }

    function onRequestFinished(message) {
        if (isReasoning) {
            isReasoning = false;
            appendText(message, "\n\n</think>\n\n");
        }
        if (!sawToolCalls) return {};

        // Ai.qml handles one call per turn; use the first complete one
        const first = pendingToolCalls[Object.keys(pendingToolCalls).sort()[0]];
        if (!first || !first.name) return {};
        let args = {};
        try {
            args = first.arguments.trim().length > 0 ? JSON.parse(first.arguments) : {};
        } catch (e) {
            appendText(message, `\n\n**Error**: model sent invalid arguments for ${first.name}: ${first.arguments}`);
            return {};
        }
        const callId = first.id || `call_${Math.random().toString(36).slice(2, 10)}`;
        appendText(message, `\n\n[[ Function: ${first.name}(${JSON.stringify(args, null, 2)}) ]]\n`);
        message.functionName = first.name;
        return { functionCall: { name: first.name, args: args, id: callId } };
    }

    function reset() {
        isReasoning = false;
        pendingToolCalls = {};
        sawToolCalls = false;
    }
}
