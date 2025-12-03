package main

type ProjectStatus string

const (
    // canonical set you already had
    ProjectStatusCreated   ProjectStatus = "created"
    ProjectStatusActive    ProjectStatus = "active"
    ProjectStatusFunded    ProjectStatus = "funded"
    ProjectStatusCompleted ProjectStatus = "completed"
    ProjectStatusCancelled ProjectStatus = "cancelled"

    // aliases to match earlier code (optional)
    StatusPending   ProjectStatus = "created"
    StatusActive    ProjectStatus = "active"
    StatusCompleted ProjectStatus = "completed"
    StatusCancelled ProjectStatus = "cancelled"
)
