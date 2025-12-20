# Basketball Analytics

A Python-based web scraping and analytics system for basketball game data from Exposure Basketball Events.

## Features

- **Web Scraping**: Automated scraping of game schedules and scores from Exposure Basketball Events website
- **Game Comparison**: Compare game data between different time periods to detect changes in date, time, or venue
- **Team Ratings**: Calculate team ratings using regularized regression (Lasso)
- **Streamlit Dashboard**: Interactive web app to view game results and team ratings

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Make sure ChromeDriver is installed for web scraping:
   - macOS: `brew install chromedriver`
   - Or download from: https://chromedriver.chromium.org/

## Usage

### Scraping Game Data

Run the scraper to extract game data:
```bash
python scrape_exposure.py
```

This will:
- Navigate to the Exposure Basketball Events schedule page
- Click on division links (e.g., "4th Girls")
- Extract game data (teams, scores, dates, times, venues)
- Save to `games_data.json`

### Analyzing Games

Run the analysis script to:
- Compare game files for changes
- Calculate team ratings
- Generate team-specific comparison CSVs

```bash
python analyze_games.py
```

### Running the Dashboard

Launch the Streamlit app:
```bash
streamlit run app.py
```

Or use the provided script:
```bash
./start-app.sh
```

## Project Structure

- `scrape_exposure.py` - Web scraper for Exposure Basketball Events
- `analyze_games.py` - Game comparison and team rating calculations
- `app.py` - Streamlit dashboard application
- `requirements.txt` - Python dependencies

## Data Files

Generated data files (excluded from git):
- `games_data.json` - Current game data
- `games_data_20251219.json` - Previous game data snapshot
- `shorewood_games_comparison.csv` - Shorewood-specific game comparison
- `team_ratings.csv` - Team ratings output

## License

Personal project for basketball analytics.

