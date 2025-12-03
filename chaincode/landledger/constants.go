package main

const (
	// Land parcel composite indexes
	ownerIndex = "owner~parcel"
	titleIndex = "title~parcel"

	// Project key prefix and composite indexes
	projectKeyPrefix = "project:"              // used by projectKey()
	projectParcelIdx = "project~parcel~id"     // parcel -> project
	projectOwnerIdx  = "project~owner~id"      // owner  -> project
)
