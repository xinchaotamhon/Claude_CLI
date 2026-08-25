package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestValidateHost(t *testing.T) {
	for _, host := range []string{"127.0.0.1", "localhost", "LOCALHOST"} {
		if err := validateHost(host); err != nil {
			t.Fatalf("validateHost(%q) returned error: %v", host, err)
		}
	}
	for _, host := range []string{"0.0.0.0", "127.0.0.2", "::1", "example.com", ""} {
		if err := validateHost(host); err == nil {
			t.Fatalf("validateHost(%q) accepted a non-approved host", host)
		}
	}
}

func TestRunRejectsNonLoopbackBeforeListening(t *testing.T) {
	if err := run("0.0.0.0", 0); err == nil {
		t.Fatal("run accepted a non-loopback host")
	}
	if err := run("localhost", -1); err == nil {
		t.Fatal("run accepted an invalid port")
	}
}

func TestHealthAndNonStreamingCompletion(t *testing.T) {
	server := httptest.NewServer(&fixtureHandler{})
	defer server.Close()

	response, err := http.Get(server.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("health status = %d", response.StatusCode)
	}
	var health map[string]any
	if err := json.NewDecoder(response.Body).Decode(&health); err != nil {
		t.Fatal(err)
	}
	if health["status"] != "ok" || health["loopback_only"] != true {
		t.Fatalf("unexpected health response: %#v", health)
	}

	body := strings.NewReader(`{"model":"fixture-test","messages":[{"role":"user","content":"hi"}]}`)
	response, err = http.Post(server.URL+"/v1/chat/completions", "application/json", body)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("completion status = %d", response.StatusCode)
	}
	var completion chatCompletion
	if err := json.NewDecoder(response.Body).Decode(&completion); err != nil {
		t.Fatal(err)
	}
	if completion.Choices[0].Message.Content != "Fixture response." {
		t.Fatalf("unexpected completion: %#v", completion)
	}
}

func TestSSEStream(t *testing.T) {
	server := httptest.NewServer(&fixtureHandler{})
	defer server.Close()
	payload := `{"model":"fixture-test","stream":true,"messages":[{"role":"user","content":"hi"}]}`
	response, err := http.Post(server.URL+"/v1/chat/completions", "application/json", strings.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.Header.Get("Content-Type") != "text/event-stream" {
		t.Fatalf("content type = %q", response.Header.Get("Content-Type"))
	}
	data, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(data, []byte(`"content":"Fixture `)) || !bytes.Contains(data, []byte("data: [DONE]")) {
		t.Fatalf("unexpected SSE body: %s", data)
	}
}

func TestSSEToolCall(t *testing.T) {
	server := httptest.NewServer(&fixtureHandler{})
	defer server.Close()
	payload := `{"model":"fixture-test","stream":true,"messages":[{"role":"user","content":"use tool"}],"tools":[{"type":"function","function":{"name":"lookup_weather"}}]}`
	response, err := http.Post(server.URL+"/v1/chat/completions", "application/json", strings.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	data, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(data, []byte(`"tool_calls"`)) || !bytes.Contains(data, []byte(`"finish_reason":"tool_calls"`)) || !bytes.Contains(data, []byte("data: [DONE]")) {
		t.Fatalf("unexpected tool SSE body: %s", data)
	}
}

func TestToolCallThenToolResult(t *testing.T) {
	server := httptest.NewServer(&fixtureHandler{})
	defer server.Close()

	firstPayload := `{"model":"fixture-test","messages":[{"role":"user","content":"use tool"}],"tools":[{"type":"function","function":{"name":"lookup_weather"}}]}`
	response, err := http.Post(server.URL+"/v1/chat/completions", "application/json", strings.NewReader(firstPayload))
	if err != nil {
		t.Fatal(err)
	}
	var first chatCompletion
	if err := json.NewDecoder(response.Body).Decode(&first); err != nil {
		response.Body.Close()
		t.Fatal(err)
	}
	response.Body.Close()
	if first.Choices[0].FinishReason != "tool_calls" || len(first.Choices[0].Message.ToolCalls) != 1 {
		t.Fatalf("unexpected tool call response: %#v", first)
	}
	if first.Choices[0].Message.ToolCalls[0].Function.Name != "lookup_weather" {
		t.Fatalf("tool name was not preserved: %#v", first)
	}

	secondPayload := `{"model":"fixture-test","messages":[{"role":"user","content":"use tool"},{"role":"assistant","content":null,"tool_calls":[{"id":"call_fixture_echo","type":"function","function":{"name":"lookup_weather","arguments":"{}"}}]},{"role":"tool","tool_call_id":"call_fixture_echo","content":"sunny"}]}`
	response, err = http.Post(server.URL+"/v1/chat/completions", "application/json", strings.NewReader(secondPayload))
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var second chatCompletion
	if err := json.NewDecoder(response.Body).Decode(&second); err != nil {
		t.Fatal(err)
	}
	if second.Choices[0].FinishReason != "stop" || second.Choices[0].Message.Content != "Fixture tool result received." {
		t.Fatalf("unexpected tool result response: %#v", second)
	}
}

func TestUnsupportedRouteAndMethod(t *testing.T) {
	server := httptest.NewServer(&fixtureHandler{})
	defer server.Close()
	response, err := http.Get(server.URL + "/not-found")
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusNotFound {
		t.Fatalf("not-found status = %d", response.StatusCode)
	}
	response, err = http.Post(server.URL+"/health", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("wrong-method status = %d", response.StatusCode)
	}
}

func TestNoRequestLoggingByHandler(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	recorder := httptest.NewRecorder()
	(&fixtureHandler{}).ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("handler status = %d", recorder.Code)
	}
	if strings.Contains(recorder.Body.String(), "credential") || strings.Contains(recorder.Body.String(), "secret") {
		t.Fatalf("health response contains a forbidden credential-shaped value: %s", recorder.Body.String())
	}
}
