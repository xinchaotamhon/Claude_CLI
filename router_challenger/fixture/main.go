// Command fixture is a deterministic, loopback-only OpenAI-compatible upstream
// for the challenger pilot. It never makes outbound requests and never writes
// request bodies, credentials, or logs to disk.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
)

const (
	defaultHost       = "127.0.0.1"
	defaultPort       = 8787
	maxRequestBody    = 1 << 20
	fixtureModel      = "fixture-model"
	defaultToolName   = "fixture_echo"
	toolCallID        = "call_fixture_echo"
	fixtureHealthName = "claude-cli-router-fixture"
)

type fixtureHandler struct {
	sequence uint64
}

type chatRequest struct {
	Model    string            `json:"model"`
	Messages []chatMessage     `json:"messages"`
	Stream   bool              `json:"stream"`
	Tools    []json.RawMessage `json:"tools"`
}

type chatMessage struct {
	Role string `json:"role"`
}

type chatCompletion struct {
	ID      string          `json:"id"`
	Object  string          `json:"object"`
	Created int64           `json:"created"`
	Model   string          `json:"model"`
	Choices []chatChoice    `json:"choices"`
	Usage   completionUsage `json:"usage"`
}

type chatChoice struct {
	Index        int              `json:"index"`
	Message      assistantMessage `json:"message"`
	FinishReason string           `json:"finish_reason"`
}

type assistantMessage struct {
	Role      string     `json:"role"`
	Content   any        `json:"content"`
	ToolCalls []toolCall `json:"tool_calls,omitempty"`
}

type completionUsage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
	TotalTokens      int `json:"total_tokens"`
}

type toolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"`
	Function toolFunction `json:"function"`
}

type toolFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type streamChunk struct {
	ID      string         `json:"id"`
	Object  string         `json:"object"`
	Created int64          `json:"created"`
	Model   string         `json:"model"`
	Choices []streamChoice `json:"choices"`
}

type streamChoice struct {
	Index        int         `json:"index"`
	Delta        streamDelta `json:"delta"`
	FinishReason *string     `json:"finish_reason"`
}

type streamDelta struct {
	Role      string           `json:"role,omitempty"`
	Content   string           `json:"content,omitempty"`
	ToolCalls []streamToolCall `json:"tool_calls,omitempty"`
}

type streamToolCall struct {
	Index    int          `json:"index"`
	ID       string       `json:"id,omitempty"`
	Type     string       `json:"type,omitempty"`
	Function toolFunction `json:"function,omitempty"`
}

func validateHost(host string) error {
	switch strings.ToLower(strings.TrimSpace(host)) {
	case "127.0.0.1", "localhost":
		return nil
	default:
		return fmt.Errorf("host %q is not allowed; use 127.0.0.1 or localhost", host)
	}
}

func (h *fixtureHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/health":
		if r.Method != http.MethodGet {
			methodNotAllowed(w, http.MethodGet)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"status":        "ok",
			"service":       fixtureHealthName,
			"loopback_only": true,
		})
	case "/v1/chat/completions":
		if r.Method != http.MethodPost {
			methodNotAllowed(w, http.MethodPost)
			return
		}
		h.handleChatCompletions(w, r)
	default:
		writeError(w, http.StatusNotFound, "not_found", "fixture endpoint not found")
	}
}

func (h *fixtureHandler) handleChatCompletions(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, maxRequestBody+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read_error", "could not read request")
		return
	}
	if len(body) > maxRequestBody {
		writeError(w, http.StatusRequestEntityTooLarge, "request_too_large", "request body is too large")
		return
	}
	var request chatRequest
	if err := json.Unmarshal(body, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	model := request.Model
	if model == "" {
		model = fixtureModel
	}
	requestID := fmt.Sprintf("chatcmpl-fixture-%d", atomic.AddUint64(&h.sequence, 1))
	toolResult := hasToolResult(request.Messages)
	if request.Stream {
		h.writeStream(w, requestID, model, len(request.Tools) > 0 && !toolResult, toolName(request.Tools), toolResult)
		return
	}
	writeJSON(w, http.StatusOK, makeCompletion(requestID, model, len(request.Tools) > 0 && !toolResult, toolName(request.Tools), toolResult))
}

func hasToolResult(messages []chatMessage) bool {
	for _, message := range messages {
		if message.Role == "tool" {
			return true
		}
	}
	return false
}

func toolName(tools []json.RawMessage) string {
	for _, raw := range tools {
		var definition struct {
			Function struct {
				Name string `json:"name"`
			} `json:"function"`
		}
		if json.Unmarshal(raw, &definition) == nil && definition.Function.Name != "" {
			return definition.Function.Name
		}
	}
	return defaultToolName
}

func makeCompletion(id, model string, needsTool bool, name string, toolResult bool) chatCompletion {
	if needsTool {
		return chatCompletion{
			ID: id, Object: "chat.completion", Created: 0, Model: model,
			Choices: []chatChoice{{
				Index: 0,
				Message: assistantMessage{
					Role: "assistant", Content: nil,
					ToolCalls: []toolCall{{ID: toolCallID, Type: "function", Function: toolFunction{
						Name: name, Arguments: `{"text":"fixture tool call"}`,
					}}},
				},
				FinishReason: "tool_calls",
			}},
			Usage: completionUsage{},
		}
	}
	content := "Fixture response."
	if toolResult {
		content = "Fixture tool result received."
	}
	return chatCompletion{
		ID: id, Object: "chat.completion", Created: 0, Model: model,
		Choices: []chatChoice{{
			Index:        0,
			Message:      assistantMessage{Role: "assistant", Content: content},
			FinishReason: "stop",
		}},
		Usage: completionUsage{},
	}
}

func (h *fixtureHandler) writeStream(w http.ResponseWriter, id, model string, needsTool bool, name string, toolResult bool) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "close")
	w.WriteHeader(http.StatusOK)
	flusher, ok := w.(http.Flusher)
	if !ok {
		return
	}
	writeSSE(w, flusher, streamChunk{
		ID: id, Object: "chat.completion.chunk", Created: 0, Model: model,
		Choices: []streamChoice{{Index: 0, Delta: streamDelta{Role: "assistant"}}},
	})
	if needsTool {
		writeSSE(w, flusher, streamChunk{
			ID: id, Object: "chat.completion.chunk", Created: 0, Model: model,
			Choices: []streamChoice{{Index: 0, Delta: streamDelta{ToolCalls: []streamToolCall{{
				Index: 0, ID: toolCallID, Type: "function",
				Function: toolFunction{Name: name, Arguments: `{"text":"fixture tool call"}`},
			}}}}},
		})
		finish := "tool_calls"
		writeSSE(w, flusher, streamChunk{
			ID: id, Object: "chat.completion.chunk", Created: 0, Model: model,
			Choices: []streamChoice{{Index: 0, Delta: streamDelta{}, FinishReason: &finish}},
		})
	} else {
		content := "Fixture response."
		if toolResult {
			content = "Fixture tool result received."
		}
		for _, part := range []string{"Fixture ", strings.TrimPrefix(content, "Fixture ")} {
			writeSSE(w, flusher, streamChunk{
				ID: id, Object: "chat.completion.chunk", Created: 0, Model: model,
				Choices: []streamChoice{{Index: 0, Delta: streamDelta{Content: part}}},
			})
		}
		finish := "stop"
		writeSSE(w, flusher, streamChunk{
			ID: id, Object: "chat.completion.chunk", Created: 0, Model: model,
			Choices: []streamChoice{{Index: 0, Delta: streamDelta{}, FinishReason: &finish}},
		})
	}
	fmt.Fprint(w, "data: [DONE]\n\n")
	flusher.Flush()
}

func writeSSE(w io.Writer, flusher http.Flusher, value streamChunk) {
	data, _ := json.Marshal(value)
	fmt.Fprintf(w, "data: %s\n\n", data)
	flusher.Flush()
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"error": map[string]string{"type": code, "message": message},
	})
}

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method is not supported")
}

func run(host string, port int) error {
	if err := validateHost(host); err != nil {
		return err
	}
	if port < 0 || port > 65535 {
		return errors.New("port must be between 0 and 65535")
	}
	listener, err := net.Listen("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	defer listener.Close()

	server := &http.Server{
		Handler:  &fixtureHandler{},
		ErrorLog: log.New(io.Discard, "", 0),
	}
	fmt.Printf("fixture listening on http://%s/health\n", listener.Addr().String())
	return server.Serve(listener)
}

func main() {
	host := flag.String("host", defaultHost, "loopback host: 127.0.0.1 or localhost")
	port := flag.Int("port", defaultPort, "TCP port; 0 selects an ephemeral port")
	flag.Parse()
	if err := run(*host, *port); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fmt.Fprintf(os.Stderr, "fixture error: %v\n", err)
		os.Exit(2)
	}
}
