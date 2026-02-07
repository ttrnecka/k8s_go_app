// app/main.go
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"myapp/db"
	"myapp/handlers"
	"myapp/metrics"
	"myapp/middleware"
	"myapp/session"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	// Initialize database
	database, err := db.InitDB()
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	// Initialize Redis session store
	sessionStore, err := session.NewRedisStore()
	if err != nil {
		log.Fatalf("Failed to initialize session store: %v", err)
	}
	defer sessionStore.Close()

	// Initialize metrics
	metrics.InitMetrics()

	// Setup HTTP handlers
	mux := http.NewServeMux()

	// Health endpoints
	mux.HandleFunc("/health", handlers.HealthHandler)
	mux.HandleFunc("/ready", handlers.ReadyHandler(database, sessionStore))

	// Metrics endpoint
	mux.Handle("/metrics", promhttp.Handler())

	// Auth endpoints
	authHandler := handlers.NewAuthHandler(database, sessionStore)
	mux.HandleFunc("/login", authHandler.Login)
	mux.HandleFunc("/logout", authHandler.Logout)

	// Post endpoints (require authentication)
	postHandler := handlers.NewPostHandler(database)
	mux.Handle("/post", middleware.AuthMiddleware(sessionStore, http.HandlerFunc(postHandler.CreatePost)))
	mux.Handle("/posts", middleware.AuthMiddleware(sessionStore, http.HandlerFunc(postHandler.ListPosts)))

	// Wrap with metrics middleware
	handler := middleware.MetricsMiddleware(mux)

	// HTTP Server
	srv := &http.Server{
		Addr:         ":8080",
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Server starting on :8080")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}