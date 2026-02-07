package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"myapp/metrics"
	"myapp/session"
	"net/http"
	"time"
)

func AuthMiddleware(store *session.RedisStore, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sessionID := r.Header.Get("X-Session-ID")
		if sessionID == "" {
			w.WriteHeader(http.StatusUnauthorized)
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"message": "No session ID provided",
			})
			return
		}

		sess, err := store.Get(sessionID)
		if err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": false,
				"message": "Invalid or expired session",
			})
			return
		}

		ctx := context.WithValue(r.Context(), "user_id", sess.UserID)
		ctx = context.WithValue(ctx, "username", sess.Username)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func MetricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// Wrap ResponseWriter to capture status code
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(rw, r)

		duration := time.Since(start).Seconds()

		// Record metrics
		metrics.HTTPRequestDuration.WithLabelValues(r.URL.Path, r.Method).Observe(duration)
		metrics.HTTPRequestsTotal.WithLabelValues(r.URL.Path, r.Method, fmt.Sprintf("%d", rw.statusCode)).Inc()
	})
}

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}