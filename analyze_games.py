"""
Script to:
1. Compare two game data JSON files for changes in date, time, or venue
2. Calculate team ratings using regularized regression (similar to R glmnet)
"""

import json
import pandas as pd
import numpy as np
from sklearn.linear_model import LassoCV
from datetime import datetime
import re

def load_games_data(filepath):
    """Load games data from JSON file"""
    with open(filepath, 'r', encoding='utf-8') as f:
        return json.load(f)

def normalize_team_name(team_name):
    """Normalize team name to create a key (lowercase, underscores, no apostrophes)"""
    if not team_name:
        return None
    # Convert to lowercase, trim whitespace, remove apostrophes, replace spaces with underscores
    normalized = re.sub(r"'", "", team_name.lower().strip())
    normalized = re.sub(r"\s+", "_", normalized)
    return normalized

def create_game_key(game):
    """Create a unique key for a game based on teams and date"""
    away = normalize_team_name(game.get('away_team', ''))
    home = normalize_team_name(game.get('home_team', ''))
    date = game.get('date', '')
    # Sort teams to handle home/away swaps
    teams = tuple(sorted([away, home])) if away and home else None
    return (teams, date) if teams else None

def compare_games(current_file, previous_file, team_filter="Shorewood"):
    """
    Compare two game data files and identify changes in date, time, or venue
    Optionally filter for a specific team
    
    Args:
        current_file: Path to current games JSON file
        previous_file: Path to previous games JSON file
        team_filter: Team name to filter for (default: "Shorewood")
    
    Returns:
        DataFrame with all games for the specified team and change status
    """
    print("=" * 60)
    print("Comparing Game Data Files")
    if team_filter:
        print(f"Filtering for: {team_filter}")
    print("=" * 60)
    print()
    
    current_games = load_games_data(current_file)
    previous_games = load_games_data(previous_file)
    
    print(f"Current file: {len(current_games)} games")
    print(f"Previous file: {len(previous_games)} games")
    print()
    
    # Create dictionaries keyed by game identifier
    current_dict = {}
    previous_dict = {}
    
    for game in current_games:
        key = create_game_key(game)
        if key:
            current_dict[key] = game
    
    for game in previous_games:
        key = create_game_key(game)
        if key:
            previous_dict[key] = game
    
    # Filter for team if specified
    if team_filter:
        # Get all current games for the team
        team_games = []
        for game in current_games:
            away_team = game.get('away_team', '')
            home_team = game.get('home_team', '')
            if away_team == team_filter or home_team == team_filter:
                team_games.append(game)
        
        print(f"Found {len(team_games)} games for {team_filter} in current file")
        print()
    else:
        team_games = current_games
    
    # Build output list
    output_games = []
    
    for current_game in team_games:
        key = create_game_key(current_game)
        changed = "no"
        
        if key and key in previous_dict:
            prev_game = previous_dict[key]
            
            # Check for changes
            date_changed = current_game.get('date') != prev_game.get('date')
            time_changed = current_game.get('time') != prev_game.get('time')
            venue_changed = current_game.get('venue') != prev_game.get('venue')
            court_changed = current_game.get('court') != prev_game.get('court')
            
            if date_changed or time_changed or venue_changed or court_changed:
                changed = "YES"
        else:
            # New game (not in previous file)
            changed = "YES"
        
        # Get scores, leave blank if None or empty
        home_score = current_game.get('home_score', '')
        away_score = current_game.get('away_score', '')
        if home_score is None or home_score == '':
            home_score = ''
        if away_score is None or away_score == '':
            away_score = ''
        
        output_games.append({
            'Date': current_game.get('date', ''),
            'Time': current_game.get('time', ''),
            'Venue': current_game.get('venue', ''),
            'Home Team': current_game.get('home_team', ''),
            'Away Team': current_game.get('away_team', ''),
            'Home Score': home_score,
            'Away Score': away_score,
            'CHANGED': changed
        })
    
    if output_games:
        output_df = pd.DataFrame(output_games)
        
        # Sort by date and time
        output_df['Date_Sort'] = pd.to_datetime(output_df['Date'], format='%A, %B %d, %Y', errors='coerce')
        output_df = output_df.sort_values(['Date_Sort', 'Time']).drop('Date_Sort', axis=1)
        
        # Save to CSV
        output_filename = f'{team_filter.lower()}_games_comparison.csv' if team_filter else 'game_changes.csv'
        output_df.to_csv(output_filename, index=False)
        
        print(f"Found {len(output_games)} games")
        changed_count = sum(1 for g in output_games if g['CHANGED'] == 'YES')
        print(f"  - {changed_count} with changes")
        print(f"  - {len(output_games) - changed_count} unchanged")
        print()
        print(f"Results saved to '{output_filename}'")
        print()
        
        # Print summary of changes
        if changed_count > 0:
            print("Games with changes:")
            for game in output_games:
                if game['CHANGED'] == 'YES':
                    print(f"  {game['Away Team']} @ {game['Home Team']} on {game['Date']} at {game['Time']}")
            print()
    else:
        print(f"No games found for {team_filter}")
        output_df = pd.DataFrame()
    
    print()
    return output_df

def calculate_team_ratings(games_file, margin_game_cap=99):
    """
    Calculate team ratings using regularized regression (Lasso)
    Similar to the R glmnet approach
    
    Args:
        games_file: Path to JSON file with game data
        margin_game_cap: Maximum margin to cap at (default 99)
    
    Returns:
        DataFrame with team ratings
    """
    print("=" * 60)
    print("Calculating Team Ratings")
    print("=" * 60)
    print()
    
    # Load games data
    games = load_games_data(games_file)
    
    # Convert to DataFrame
    df = pd.DataFrame(games)
    
    # Filter games with scores
    df = df[
        df['away_score'].notna() & 
        df['home_score'].notna() &
        (df['away_score'] != '') &
        (df['home_score'] != '')
    ].copy()
    
    # Convert scores to numeric
    df['away_score'] = pd.to_numeric(df['away_score'], errors='coerce')
    df['home_score'] = pd.to_numeric(df['home_score'], errors='coerce')
    
    # Remove any rows where conversion failed
    df = df[df['away_score'].notna() & df['home_score'].notna()].copy()
    
    print(f"Processing {len(df)} games with scores")
    
    if len(df) == 0:
        print("No games with valid scores found!")
        return pd.DataFrame()
    
    # Create normalized team keys
    df['home_key'] = df['home_team'].apply(normalize_team_name)
    df['away_key'] = df['away_team'].apply(normalize_team_name)
    
    # Get all unique teams
    teams = sorted(set(df['home_key'].dropna().tolist() + df['away_key'].dropna().tolist()))
    print(f"Found {len(teams)} unique teams")
    print()
    
    # Calculate home margin (capped)
    df['home_margin'] = (df['home_score'] - df['away_score']).clip(-margin_game_cap, margin_game_cap)
    
    # Create design matrix
    # Each row is a game, each column is a team
    # Home team = 1, Away team = -1, Others = 0
    n_games = len(df)
    n_teams = len(teams)
    
    X = np.zeros((n_games, n_teams))
    team_to_idx = {team: idx for idx, team in enumerate(teams)}
    
    for i, row in df.iterrows():
        home_idx = team_to_idx.get(row['home_key'])
        away_idx = team_to_idx.get(row['away_key'])
        
        if home_idx is not None:
            X[i, home_idx] = 1
        if away_idx is not None:
            X[i, away_idx] = -1
    
    y = df['home_margin'].values
    
    print(f"Design matrix shape: {X.shape}")
    print(f"Number of games: {n_games}")
    print()
    
    # Fit Lasso regression with cross-validation
    print("Fitting regularized regression model...")
    # Use LassoCV which is similar to cv.glmnet
    # n_folds similar to nfolds in R
    n_folds = max(3, min(10, n_games // 2))  # Similar to R: length(df_matrix$home_margin) %/% 2
    
    lasso_model = LassoCV(
        cv=n_folds,
        random_state=42,
        n_jobs=-1,
        max_iter=5000
    )
    
    lasso_model.fit(X, y)
    
    # Get coefficients (ratings)
    # Use lambda.1se equivalent - this is the largest lambda within 1 SE of minimum
    # In sklearn, we can use alpha_ (the chosen alpha) or get the path
    coefficients = lasso_model.coef_
    intercept = lasso_model.intercept_
    
    # Create ratings DataFrame
    ratings_df = pd.DataFrame({
        'Team': teams,
        'xMargin': coefficients
    })
    
    # Center the ratings (subtract mean)
    ratings_df['xMargin'] = ratings_df['xMargin'] - ratings_df['xMargin'].mean()
    
    # Format and sort
    ratings_df = ratings_df.sort_values('xMargin', ascending=False)
    ratings_df['xMargin'] = ratings_df['xMargin'].round(2)
    
    # Convert team keys back to original names (or keep normalized)
    # For now, keep normalized keys, but you can map back if needed
    
    print("Team Ratings (sorted by rating):")
    print()
    print(ratings_df.to_string(index=False))
    print()
    
    # Save to CSV
    ratings_df.to_csv('team_ratings.csv', index=False)
    print("Ratings saved to 'team_ratings.csv'")
    print()
    
    return ratings_df

def main():
    """Main function"""
    current_file = "games_data.json"
    previous_file = "games_data_20251219.json"
    team_filter = "Shorewood"  # Set to None to compare all games
    
    try:
        # Part 1: Compare files (filtered for Shorewood)
        changes_df = compare_games(current_file, previous_file, team_filter=team_filter)
        
        # Part 2: Calculate team ratings
        ratings_df = calculate_team_ratings(current_file)
        
        print("=" * 60)
        print("Analysis Complete!")
        print("=" * 60)
        
    except FileNotFoundError as e:
        print(f"Error: File not found - {e}")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()

