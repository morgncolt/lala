import json
from pathlib import Path

# Generate sample GeoJSON FeatureCollection with dummy polygon data
def create_sample_geojson(region_name, coordinates, owner, title_number, description):
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "owner": owner,
                    "title_number": title_number,
                    "description": description
                },
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [coordinates]
                }
            }
        ]
    }

# Example rough polygons for each region (not geographically accurate)
ghana_coords = [[[-0.1, 5.5], [-0.15, 5.55], [-0.1, 5.6], [0.0, 5.55], [-0.1, 5.5]]]
cameroon_coords = [[[11.5, 3.8], [11.6, 3.85], [11.5, 3.9], [11.4, 3.85], [11.5, 3.8]]]
nigeria_abj_coords = [[[7.3, 9.0], [7.4, 9.05], [7.3, 9.1], [7.2, 9.05], [7.3, 9.0]]]
nigeria_lagos_coords = [[[3.3, 6.4], [3.35, 6.45], [3.3, 6.5], [3.25, 6.45], [3.3, 6.4]]]
kenya_coords = [[[36.8, -1.3], [36.85, -1.25], [36.9, -1.3], [36.85, -1.35], [36.8, -1.3]]]

# Create GeoJSON files
geojson_files = {
    "ghana.geojson": create_sample_geojson("Ghana", ghana_coords, "Kwame Nkrumah", "GH-001", "Accra plot A"),
    "cameroon.geojson": create_sample_geojson("Cameroon", cameroon_coords, "Paul Biya", "CM-001", "Yaoundé central"),
    "nigeria_abj.geojson": create_sample_geojson("Nigeria Abuja", nigeria_abj_coords, "Amaka Obi", "NG-ABJ-001", "Abuja FCT"),
    "nigeria_lagos.geojson": create_sample_geojson("Nigeria Lagos", nigeria_lagos_coords, "Tunde Balogun", "NG-LAG-001", "Lekki Phase 1"),
    "kenya.geojson": create_sample_geojson("Kenya", kenya_coords, "Wangari Maathai", "KE-001", "Nairobi South B"),
}

output_dir = Path("/home/labuser/lala/landledger_frontend/assets/data")
output_dir.mkdir(parents=True, exist_ok=True)

# Write files
for filename, data in geojson_files.items():
    with open(output_dir / filename, 'w') as f:
        json.dump(data, f, indent=2)

for file in output_dir.iterdir():
    if file.is_file():
        print(file.name)

