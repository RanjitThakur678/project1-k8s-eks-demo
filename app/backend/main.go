package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync/atomic"
)

// requestCount is incremented per pod to visualize load-balancing spread across replicas.
var requestCount int64

type infoResponse struct {
	PodName    string `json:"pod_name"`
	PodIP      string `json:"pod_ip"`
	NodeName   string `json:"node_name"`
	Requests   int64  `json:"requests_served_by_this_pod"`
	AppVersion string `json:"app_version"`
}

func infoHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddInt64(&requestCount, 1)

	resp := infoResponse{
		PodName:    envOrDefault("POD_NAME", "unknown"),
		PodIP:      envOrDefault("POD_IP", "unknown"),
		NodeName:   envOrDefault("NODE_NAME", "unknown"),
		Requests:   atomic.LoadInt64(&requestCount),
		AppVersion: envOrDefault("APP_VERSION", "v1"),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

type tour struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Price       int    `json:"price_usd"`
	Emoji       string `json:"emoji"`
	Days        int    `json:"days"`
}

// Static sample data - a small "tour shop" catalog to give the demo something to look at.
var tours = []tour{
	{ID: "himalaya-trek", Name: "Himalaya Base Camp Trek", Description: "Guided trek through pine forests and alpine meadows.", Price: 899, Emoji: "🏔️", Days: 7},
	{ID: "coastal-cruise", Name: "Coastal Sunset Cruise", Description: "Evening cruise along the coastline with dinner onboard.", Price: 149, Emoji: "🛳️", Days: 1},
	{ID: "desert-safari", Name: "Desert Dune Safari", Description: "Jeep safari, camel ride, and a night under the stars.", Price: 249, Emoji: "🐫", Days: 2},
	{ID: "rainforest-canopy", Name: "Rainforest Canopy Walk", Description: "Zip-lines and canopy bridges through the jungle.", Price: 179, Emoji: "🌴", Days: 1},
	{ID: "city-heritage", Name: "Old City Heritage Walk", Description: "Guided walking tour through the historic old quarter.", Price: 59, Emoji: "🏛️", Days: 1},
	{ID: "island-diving", Name: "Island Reef Diving", Description: "Certified dive trip to a protected coral reef.", Price: 329, Emoji: "🤿", Days: 3},
}

func toursHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(tours)
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/info", infoHandler)
	mux.HandleFunc("/api/tours", toursHandler)
	mux.HandleFunc("/healthz", healthzHandler)
	mux.Handle("/", http.FileServer(http.Dir("./static")))

	addr := ":8080"
	log.Printf("listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
