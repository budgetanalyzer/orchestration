package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	corev3 "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	authv3 "github.com/envoyproxy/go-control-plane/envoy/service/auth/v3"
	typev3 "github.com/envoyproxy/go-control-plane/envoy/type/v3"
	"google.golang.org/grpc/codes"
	grpcstatus "google.golang.org/grpc/status"
)

// AuthServer implements the Envoy ext_authz gRPC Authorization service.
type AuthServer struct {
	authv3.UnimplementedAuthorizationServer
	store      *SessionStore
	cookieName string
	enforce    bool
}

func NewAuthServer(store *SessionStore, cfg Config) *AuthServer {
	return &AuthServer{
		store:      store,
		cookieName: cfg.SessionCookieName,
		enforce:    cfg.EnforceMode,
	}
}

func (s *AuthServer) Check(ctx context.Context, req *authv3.CheckRequest) (*authv3.CheckResponse, error) {
	httpReq := req.GetAttributes().GetRequest().GetHttp()
	path := httpReq.GetPath()
	method := httpReq.GetMethod()
	mode := "observe"
	if s.enforce {
		mode = "enforce"
	}

	// Extract session cookie from request headers
	sessionID := s.extractSessionCookie(httpReq.GetHeaders())
	if sessionID == "" {
		slog.Warn("no session cookie",
			"path", path,
			"method", method,
			"decision", s.decisionLabel(false),
			"mode", mode,
		)
		if s.enforce {
			return deniedResponse(typev3.StatusCode_Unauthorized, "no session cookie"), nil
		}
		return allowedResponse(nil), nil
	}

	// Look up session in Redis
	session, err := s.store.LookupSession(ctx, sessionID)
	if err != nil {
		if errors.Is(err, ErrSessionNotFound) {
			slog.Warn("session not found",
				"path", path,
				"method", method,
				"decision", s.decisionLabel(false),
				"mode", mode,
			)
			if s.enforce {
				return deniedResponse(typev3.StatusCode_Unauthorized, "session not found"), nil
			}
			return allowedResponse(nil), nil
		}

		if errors.Is(err, ErrSessionExpired) {
			slog.Warn("session expired",
				"path", path,
				"method", method,
				"decision", s.decisionLabel(false),
				"mode", mode,
			)
			if s.enforce {
				return deniedResponse(typev3.StatusCode_Unauthorized, "session expired"), nil
			}
			return allowedResponse(nil), nil
		}

		// Redis error or timeout
		slog.Error("redis error",
			"error", err,
			"path", path,
			"method", method,
			"decision", s.decisionLabel(false),
			"mode", mode,
		)
		if s.enforce {
			return deniedResponse(typev3.StatusCode_ServiceUnavailable, "internal error"), nil
		}
		return allowedResponse(nil), nil
	}

	// Session found — inject identity headers
	slog.Info("session found, injecting headers",
		"user_id", session.UserID,
		"path", path,
		"method", method,
		"decision", "allow",
		"mode", mode,
	)

	headers := []*corev3.HeaderValueOption{
		{Header: &corev3.HeaderValue{Key: "X-User-Id", Value: session.UserID}},
		{Header: &corev3.HeaderValue{Key: "X-Roles", Value: session.Roles}},
		{Header: &corev3.HeaderValue{Key: "X-Permissions", Value: session.Permissions}},
	}

	return allowedResponse(headers), nil
}

// decisionLabel returns the log label for the auth decision.
func (s *AuthServer) decisionLabel(success bool) string {
	if success || !s.enforce {
		return "allow"
	}
	return "deny"
}

// extractSessionCookie parses the cookie header and returns the session ID.
func (s *AuthServer) extractSessionCookie(headers map[string]string) string {
	cookieHeader, ok := headers["cookie"]
	if !ok {
		return ""
	}
	fakeReq := &http.Request{Header: http.Header{"Cookie": {cookieHeader}}}
	for _, c := range fakeReq.Cookies() {
		if c.Name == s.cookieName {
			return c.Value
		}
	}
	return ""
}

func allowedResponse(headers []*corev3.HeaderValueOption) *authv3.CheckResponse {
	okResp := &authv3.OkHttpResponse{}
	if len(headers) > 0 {
		okResp.Headers = headers
		// Strip any spoofed identity headers from the original request
		okResp.HeadersToRemove = []string{"X-User-Id", "X-Roles", "X-Permissions"}
	}
	return &authv3.CheckResponse{
		Status: grpcstatus.New(codes.OK, "").Proto(),
		HttpResponse: &authv3.CheckResponse_OkResponse{
			OkResponse: okResp,
		},
	}
}

func deniedResponse(statusCode typev3.StatusCode, body string) *authv3.CheckResponse {
	return &authv3.CheckResponse{
		Status: grpcstatus.New(codes.PermissionDenied, body).Proto(),
		HttpResponse: &authv3.CheckResponse_DeniedResponse{
			DeniedResponse: &authv3.DeniedHttpResponse{
				Status: &typev3.HttpStatus{Code: statusCode},
				Body:   body,
			},
		},
	}
}
