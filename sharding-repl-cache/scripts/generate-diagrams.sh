#!/bin/bash

# Script to generate all diagrams locally
# Requires: npm install -g @mermaid-js/mermaid-cli

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p diagrams/output

echo -e "${BLUE}Generating diagrams...${NC}"

# Generate PNG and SVG for each Mermaid file
for file in diagrams/*.mmd; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" .mmd)
        echo -e "${GREEN}Processing $filename...${NC}"
        
        # Generate PNG
        mmdc -i "$file" -o "diagrams/output/${filename}.png" -b white \
            -p puppeteer-config.json
        echo "  ✓ Generated ${filename}.png"
        
        # Generate SVG
        mmdc -i "$file" -o "diagrams/output/${filename}.svg" -b white \
            -p puppeteer-config.json
        echo "  ✓ Generated ${filename}.svg"
    fi
done

echo -e "${GREEN}All diagrams generated successfully!${NC}"
echo "Output location: diagrams/output/"

