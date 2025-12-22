"""
Calculate team ratings using Ordinary Least Squares (OLS) regression
No regularization penalty - unpenalized ratings
"""

import json
import pandas as pd
import numpy as np
from sklearn.linear_model import LinearRegression
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

def calculate_ols_team_ratings(games_file, margin_game_cap=99):
    """
    Calculate team ratings using Ordinary Least Squares (OLS) regression
    No regularization penalty - unpenalized ratings
    
    Args:
        games_file: Path to JSON file with game data
        margin_game_cap: Maximum margin to cap at (default 99)
    
    Returns:
        DataFrame with team ratings
    """
    print("=" * 60)
    print("Calculating Team Ratings (OLS - Unpenalized)")
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
    
    # Fit OLS regression (no regularization)
    print("Fitting OLS regression model (unpenalized)...")
    
    # Note: We need to drop one team to avoid perfect multicollinearity
    # The design matrix has a linear dependency (sum of all teams = 0)
    # We'll drop the last team and set it as the reference (rating = 0)
    X_reduced = X[:, :-1]  # Drop last team column
    
    ols_model = LinearRegression(fit_intercept=True)
    ols_model.fit(X_reduced, y)
    
    # Get coefficients (ratings)
    coefficients = np.zeros(n_teams)
    coefficients[:-1] = ols_model.coef_  # First n-1 teams get their coefficients
    coefficients[-1] = 0  # Last team is reference (rating = 0)
    intercept = ols_model.intercept_
    
    print(f"Intercept (home court advantage): {intercept:.2f}")
    print()
    
    # Create ratings DataFrame
    ratings_df = pd.DataFrame({
        'Team': teams,
        'xMargin': coefficients
    })
    
    # Center the ratings (subtract mean) so they sum to zero
    ratings_df['xMargin'] = ratings_df['xMargin'] - ratings_df['xMargin'].mean()
    
    # Format and sort
    ratings_df = ratings_df.sort_values('xMargin', ascending=False)
    ratings_df['xMargin'] = ratings_df['xMargin'].round(2)
    
    print("Team Ratings (sorted by rating):")
    print()
    print(ratings_df.to_string(index=False))
    print()
    
    # Save to CSV
    output_file = 'team_ratings_ols.csv'
    ratings_df.to_csv(output_file, index=False)
    print(f"Ratings saved to '{output_file}'")
    print()
    
    # Print some model statistics
    y_pred = ols_model.predict(X_reduced)
    r_squared = ols_model.score(X_reduced, y)
    rmse = np.sqrt(np.mean((y - y_pred) ** 2))
    
    print("Model Statistics:")
    print(f"  R-squared: {r_squared:.4f}")
    print(f"  RMSE: {rmse:.2f}")
    print(f"  Home court advantage: {intercept:.2f} points")
    print()
    
    return ratings_df

def main():
    """Main function"""
    games_file = "games_data.json"
    
    try:
        ratings_df = calculate_ols_team_ratings(games_file)
        
        print("=" * 60)
        print("OLS Analysis Complete!")
        print("=" * 60)
        
    except FileNotFoundError as e:
        print(f"Error: File not found - {e}")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()

