"""
Script to:
1. Compare two game data JSON files for changes in date, time, or venue
2. Calculate team ratings using regularized regression (similar to R glmnet)
"""

import json
import pandas as pd
import numpy as np
from sklearn.linear_model import ElasticNetCV
from datetime import datetime
import re
import os

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

def compare_games(current_file, previous_file=None, team_filter="Shorewood"):
    """
    Compare two game data files and identify changes in date, time, or venue
    Optionally filter for a specific team
    
    Args:
        current_file: Path to current games JSON file
        previous_file: Path to previous games JSON file (optional, if None, all games marked as changed)
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
    
    if previous_file and os.path.exists(previous_file):
        previous_games = load_games_data(previous_file)
        print(f"Current file: {len(current_games)} games")
        print(f"Previous file: {len(previous_games)} games")
        print()
    else:
        previous_games = []
        print(f"Current file: {len(current_games)} games")
        print("Previous file: Not found (all games will be marked as changed)")
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
        
        # Note: CSV saving is now handled in main() to support multiple grade levels
        # output_filename = f'{team_filter.lower()}_games_comparison.csv' if team_filter else 'game_changes.csv'
        # output_df.to_csv(output_filename, index=False)
        
        print(f"Found {len(output_games)} games")
        changed_count = sum(1 for g in output_games if g['CHANGED'] == 'YES')
        print(f"  - {changed_count} with changes")
        print(f"  - {len(output_games) - changed_count} unchanged")
        print()
        # Note: File saving is now handled in main() to support multiple grade levels
        # print(f"Results saved to '{output_filename}'")
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

def calculate_ols_ratings(games_file, margin_game_cap=99):
    """
    Calculate team ratings using OLS (unpenalized) regression
    Helper function to get OLS ratings for use in regularized model
    
    Args:
        games_file: Path to JSON file with game data
        margin_game_cap: Maximum margin to cap at (default 99)
    
    Returns:
        Dictionary mapping team keys to OLS ratings
    """
    from sklearn.linear_model import LinearRegression
    
    # Load games data
    games = load_games_data(games_file)
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
    df = df[df['away_score'].notna() & df['home_score'].notna()].copy()
    
    if len(df) == 0:
        return {}
    
    # Create normalized team keys
    df['home_key'] = df['home_team'].apply(normalize_team_name)
    df['away_key'] = df['away_team'].apply(normalize_team_name)
    
    # Get all unique teams
    teams = sorted(set(df['home_key'].dropna().tolist() + df['away_key'].dropna().tolist()))
    
    # Calculate home margin (capped)
    df['home_margin'] = (df['home_score'] - df['away_score']).clip(-margin_game_cap, margin_game_cap)
    
    # Create design matrix
    n_games = len(df)
    n_teams = len(teams)
    X = np.zeros((n_games, n_teams))
    team_to_idx = {team: idx for idx, team in enumerate(teams)}
    
    # Use enumerate to get sequential row index (df.iterrows() returns DataFrame index which may not be sequential)
    for row_idx, (_, row) in enumerate(df.iterrows()):
        home_idx = team_to_idx.get(row['home_key'])
        away_idx = team_to_idx.get(row['away_key'])
        if home_idx is not None:
            X[row_idx, home_idx] = 1
        if away_idx is not None:
            X[row_idx, away_idx] = -1
    
    y = df['home_margin'].values
    
    # Fit OLS (drop last team to avoid perfect multicollinearity)
    X_reduced = X[:, :-1]
    ols_model = LinearRegression(fit_intercept=True)
    ols_model.fit(X_reduced, y)
    
    # Get coefficients and center them
    coefficients = np.zeros(n_teams)
    coefficients[:-1] = ols_model.coef_
    coefficients = coefficients - coefficients.mean()  # Center
    
    # Return as dictionary
    return {team: float(coefficients[idx]) for idx, team in enumerate(teams)}

def calculate_team_ratings(games_file, margin_game_cap=99, use_lambda_1se=False, ols_ratings=None):
    """
    Calculate team ratings using regularized regression (Elastic Net)
    Uses 50% L1 (Lasso) and 50% L2 (Ridge) penalty
    Similar to the R glmnet approach with alpha=0.5
    
    Args:
        games_file: Path to JSON file with game data
        margin_game_cap: Maximum margin to cap at (default 99)
        use_lambda_1se: If True, use 1-SE rule (lambda.1se). If False, use minimum error (lambda.min) (default: False)
        ols_ratings: Optional dictionary of OLS ratings (team_key -> rating) for reference/comparison
    
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
    
    # Use enumerate to get sequential row index (df.iterrows() returns DataFrame index which may not be sequential)
    for row_idx, (_, row) in enumerate(df.iterrows()):
        home_idx = team_to_idx.get(row['home_key'])
        away_idx = team_to_idx.get(row['away_key'])
        
        if home_idx is not None:
            X[row_idx, home_idx] = 1
        if away_idx is not None:
            X[row_idx, away_idx] = -1
    
    y = df['home_margin'].values
    
    print(f"Design matrix shape: {X.shape}")
    print(f"Number of games: {n_games}")
    print()
    
    # Fit Elastic Net regression with cross-validation
    print("Fitting Elastic Net regression model (50% L1, 50% L2)...")
    # Use ElasticNetCV with l1_ratio=0.5 for 50% mixing parameter
    # n_folds similar to nfolds in R
    n_folds = max(3, min(10, n_games // 2))  # Similar to R: length(df_matrix$home_margin) %/% 2
    
    elastic_net_model = ElasticNetCV(
        l1_ratio=0.5,  # 50% L1 (Lasso), 50% L2 (Ridge)
        cv=n_folds,
        random_state=42,
        n_jobs=-1,
        max_iter=5000
    )
    
    elastic_net_model.fit(X, y)
    
    # Get coefficients (ratings)
    if use_lambda_1se:
        # Use 1-SE rule: largest alpha within 1 SE of minimum error
        # This is similar to lambda.1se in R's glmnet
        mse_path = elastic_net_model.mse_path_  # Shape: (n_alphas, n_folds)
        mean_mse = mse_path.mean(axis=1)  # Mean MSE across folds for each alpha
        std_mse = mse_path.std(axis=1)  # Std of MSE across folds
        
        min_mse_idx = np.argmin(mean_mse)
        min_mse = mean_mse[min_mse_idx]
        min_mse_std = std_mse[min_mse_idx]
        
        # Find largest alpha within 1 SE of minimum
        threshold = min_mse + min_mse_std
        valid_indices = np.where(mean_mse <= threshold)[0]
        
        if len(valid_indices) > 0:
            lambda_1se_idx = valid_indices[-1]  # Largest alpha (last index since alphas are in descending order)
            alpha_1se = elastic_net_model.alphas_[lambda_1se_idx]
            
            # Refit with lambda.1se alpha
            from sklearn.linear_model import ElasticNet
            model_1se = ElasticNet(l1_ratio=0.5, alpha=alpha_1se, max_iter=5000)
            model_1se.fit(X, y)
            coefficients = model_1se.coef_
            intercept = model_1se.intercept_
            
            print(f"Using lambda.1se rule: alpha = {alpha_1se:.6f}")
            print(f"  (Minimum error alpha = {elastic_net_model.alpha_:.6f})")
        else:
            # Fallback to minimum if 1-SE rule doesn't work
            print("Warning: Could not apply 1-SE rule, using minimum error alpha")
            coefficients = elastic_net_model.coef_
            intercept = elastic_net_model.intercept_
    else:
        # Use minimum error alpha (default, similar to lambda.min in R)
        coefficients = elastic_net_model.coef_
        intercept = elastic_net_model.intercept_
        print(f"Using minimum error alpha: {elastic_net_model.alpha_:.6f}")
    
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
    
    # Add OLS ratings column if provided
    if ols_ratings:
        ratings_df['OLS_Rating'] = ratings_df['Team'].map(ols_ratings).round(2)
        # Reorder columns: Team, Elastic Net Rating, OLS Rating
        ratings_df = ratings_df[['Team', 'xMargin', 'OLS_Rating']]
        print("Team Ratings (Elastic Net vs OLS, sorted by Elastic Net rating):")
    else:
        print("Team Ratings (sorted by rating):")
    print()
    print(ratings_df.to_string(index=False))
    print()
    
    # Note: CSV saving is now handled in main() to support multiple grade levels
    # ratings_df.to_csv('team_ratings.csv', index=False)
    # print("Ratings saved to 'team_ratings.csv'")
    print()
    
    return ratings_df

def main():
    """Main function"""
    import os
    
    # All grade levels to analyze
    grade_levels = ["4th Girls", "5th Girls", "6th Girls", "7th Girls", "8th Girls"]
    team_filter = "Shorewood"  # Set to None to compare all games
    
    print("=" * 60)
    print("Basketball Analytics - Multi-Grade Analysis")
    print("=" * 60)
    print()
    
    # Process each grade level
    for grade_level in grade_levels:
        grade_dir = grade_level.lower().replace(" ", "_")
        current_file = os.path.join(grade_dir, "games_data.json")
        
        # Check if previous file exists (using a pattern that might exist)
        previous_file = os.path.join(grade_dir, "games_data_prior.json")
        if not os.path.exists(previous_file):
            # Try to find any previous file in the directory
            prev_files = [f for f in os.listdir(grade_dir) if f.startswith("games_data_") and f != "games_data.json"]
            if prev_files:
                previous_file = os.path.join(grade_dir, sorted(prev_files)[-1])  # Use most recent
            else:
                previous_file = None
        
        print("\n" + "=" * 60)
        print(f"Analyzing {grade_level}")
        print("=" * 60)
        print()
        
        if not os.path.exists(current_file):
            print(f"Warning: {current_file} not found. Skipping {grade_level}.")
            continue
        
        try:
            # Part 1: Compare files (filtered for Shorewood)
            changes_df = compare_games(current_file, previous_file, team_filter=team_filter)
            # Save comparison to grade directory
            if not changes_df.empty:
                if team_filter:
                    output_filename = os.path.join(grade_dir, f'{team_filter.lower()}_games_comparison.csv')
                else:
                    output_filename = os.path.join(grade_dir, 'game_changes.csv')
                changes_df.to_csv(output_filename, index=False)
                print(f"Comparison saved to '{output_filename}'")
            
            # Part 2: Calculate OLS ratings first
            print("\n" + "=" * 60)
            print(f"Calculating OLS Ratings for {grade_level} (for reference)")
            print("=" * 60)
            print()
            ols_ratings = calculate_ols_ratings(current_file)
            if ols_ratings:
                print(f"Calculated OLS ratings for {len(ols_ratings)} teams")
                print()
            
            # Part 3: Calculate team ratings with Elastic Net (using OLS as input)
            ratings_df = calculate_team_ratings(current_file, use_lambda_1se=False, ols_ratings=ols_ratings)
            
            # Save ratings to grade directory
            if not ratings_df.empty:
                ratings_file = os.path.join(grade_dir, "team_ratings.csv")
                ratings_df.to_csv(ratings_file, index=False)
                print(f"Ratings saved to '{ratings_file}'")
            
            print(f"\n{grade_level} analysis complete!")
            
        except FileNotFoundError as e:
            print(f"Error: File not found - {e}")
        except Exception as e:
            print(f"Error analyzing {grade_level}: {e}")
            import traceback
            traceback.print_exc()
    
    print("\n" + "=" * 60)
    print("All Grade Levels Analysis Complete!")
    print("=" * 60)

if __name__ == "__main__":
    main()

