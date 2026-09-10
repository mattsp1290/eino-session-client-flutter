package fixture

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestServerHealthAndGenericStream(t *testing.T) {
	server := NewServer()
	health := httptest.NewRecorder()
	server.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if health.Code != http.StatusNoContent {
		t.Fatalf("health status = %d", health.Code)
	}
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/generic/run", bytes.NewBufferString(`{"messages":[]}`))
	server.ServeHTTP(response, request)
	if response.Code != http.StatusOK || !bytes.Contains(response.Body.Bytes(), []byte("RUN_FINISHED")) {
		t.Fatalf("generic response status=%d", response.Code)
	}
}

func TestAdmissionUsesOnlyNewMessage(t *testing.T) {
	server := NewServer()
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/sessions/example/runs", bytes.NewBufferString(`{"message":"new text"}`))
	server.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted || !bytes.Contains(response.Body.Bytes(), []byte(`"run_id":"run-1"`)) {
		t.Fatalf("admission status=%d body=%s", response.Code, response.Body.String())
	}
}
