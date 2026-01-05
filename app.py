"""
Streamlit app for Basketball Analytics
- Tab 1: Shorewood game results and comparisons
- Tab 2: League team ratings
"""

import streamlit as st
import pandas as pd
import os
import json
import re

# Page configuration
st.set_page_config(
    page_title="Basketball Analytics",
    page_icon="🏀",
    layout="wide"
)

# Custom CSS to make tabs larger
st.markdown("""
    <style>
    .stTabs [data-baseweb="tab-list"] {
        gap: 8px;
    }
    .stTabs [data-baseweb="tab"] {
        height: 50px;
        padding: 10px 20px;
        font-size: 18px;
        font-weight: 500;
    }
    .stTabs [aria-selected="true"] {
        background-color: #f0f2f6;
    }
    </style>
    """, unsafe_allow_html=True)

# Title
st.title("🏀 Basketball Analytics Dashboard")

# Display last updated timestamp
timestamp_file = "data_timestamp.json"
if os.path.exists(timestamp_file):
    try:
        with open(timestamp_file, 'r', encoding='utf-8') as f:
            timestamp_data = json.load(f)
            last_updated = timestamp_data.get('timestamp_pst', timestamp_data.get('last_updated', 'Unknown'))
            st.caption(f"Updated {last_updated}")
    except Exception as e:
        st.caption("Update timestamp unavailable")
else:
    # Default timestamp for now (Sunday, December 21, 9:10pm PST)
    st.caption("Updated Sunday, December 21, 2025 at 09:10 PM PST")

# Check if files exist
shorewood_file = "shorewood_games_comparison.csv"
ratings_file = "team_ratings.csv"

# Create tabs
tab1, tab2 = st.tabs(["Shorewood Games", "Team Standings"])

# Tab 1: Shorewood Games
with tab1:
    st.header("Shorewood Results & Schedule Changes")
    
    if os.path.exists(shorewood_file):
        # Load data
        df = pd.read_csv(shorewood_file)
        
        # Display summary stats
        col1, col2, col3 = st.columns(3)
        
        with col1:
            st.metric("Total Games", len(df))
        
        with col2:
            changed_count = len(df[df['CHANGED'] == 'YES'])
            st.metric("Games Changed", changed_count)
        
        with col3:
            # Calculate wins and losses for Shorewood
            wins = 0
            losses = 0
            if 'Home Team' in df.columns and 'Away Team' in df.columns:
                for _, row in df.iterrows():
                    home_team = str(row.get('Home Team', ''))
                    away_team = str(row.get('Away Team', ''))
                    home_score = row.get('Home Score', '')
                    away_score = row.get('Away Score', '')
                    
                    if home_score and away_score and home_score != '' and away_score != '':
                        try:
                            home_score = float(home_score)
                            away_score = float(away_score)
                            if home_team == 'Shorewood':
                                if home_score > away_score:
                                    wins += 1
                                elif away_score > home_score:
                                    losses += 1
                            elif away_team == 'Shorewood':
                                if away_score > home_score:
                                    wins += 1
                                elif home_score > away_score:
                                    losses += 1
                        except:
                            pass
            record = f"{wins} - {losses}"
            st.metric("Record", record)
        
        st.divider()
        
        # Filter options
        col1, col2 = st.columns(2)
        
        with col1:
            show_changed_only = st.checkbox("Show only changed games", value=False)
        
        with col2:
            show_with_scores_only = st.checkbox("Show only games with scores", value=False)
        
        # Apply filters
        filtered_df = df.copy()
        
        if show_changed_only:
            filtered_df = filtered_df[filtered_df['CHANGED'] == 'YES']
        
        if show_with_scores_only:
            filtered_df = filtered_df[
                (filtered_df['Home Score'].notna()) & 
                (filtered_df['Home Score'] != '') &
                (filtered_df['Away Score'].notna()) & 
                (filtered_df['Away Score'] != '')
            ]
        
        # Display data
        if len(filtered_df) > 0:
            # Format the dataframe for display
            display_df = filtered_df.copy()
            
            # Convert scores to integers (remove decimals) - work with original data first
            def format_score(score):
                if pd.isna(score) or score == '' or str(score).strip() == '':
                    return ''
                try:
                    return int(float(str(score)))
                except (ValueError, TypeError):
                    return ''
            
            if 'Home Score' in display_df.columns:
                display_df['Home Score'] = display_df['Home Score'].apply(format_score)
            if 'Away Score' in display_df.columns:
                display_df['Away Score'] = display_df['Away Score'].apply(format_score)
            
            # Apply styling: background color for changed rows AND bold for winners
            def format_row(row):
                styles = [''] * len(row)
                col_names = list(row.index)
                
                # Set background color for changed rows
                bg_color = ''
                if row['CHANGED'] == 'YES':
                    bg_color = 'background-color: #ffcccc;'
                
                # Bold winning team and score
                home_score = row.get('Home Score', '')
                away_score = row.get('Away Score', '')
                
                # Check if we have valid scores
                try:
                    if home_score != '' and away_score != '':
                        home_score_val = int(home_score) if isinstance(home_score, (int, float)) else int(str(home_score))
                        away_score_val = int(away_score) if isinstance(away_score, (int, float)) else int(str(away_score))
                        
                        # Find column indices
                        home_team_idx = col_names.index('Home Team') if 'Home Team' in col_names else -1
                        away_team_idx = col_names.index('Away Team') if 'Away Team' in col_names else -1
                        home_score_idx = col_names.index('Home Score') if 'Home Score' in col_names else -1
                        away_score_idx = col_names.index('Away Score') if 'Away Score' in col_names else -1
                        
                        if home_score_val > away_score_val:
                            # Home team won - bold home team and home score
                            if home_team_idx >= 0:
                                styles[home_team_idx] = bg_color + ' font-weight: bold;'
                            if home_score_idx >= 0:
                                styles[home_score_idx] = bg_color + ' font-weight: bold;'
                            # Set background for other cells if changed
                            for i in range(len(styles)):
                                if i != home_team_idx and i != home_score_idx:
                                    styles[i] = bg_color
                        elif away_score_val > home_score_val:
                            # Away team won - bold away team and away score
                            if away_team_idx >= 0:
                                styles[away_team_idx] = bg_color + ' font-weight: bold;'
                            if away_score_idx >= 0:
                                styles[away_score_idx] = bg_color + ' font-weight: bold;'
                            # Set background for other cells if changed
                            for i in range(len(styles)):
                                if i != away_team_idx and i != away_score_idx:
                                    styles[i] = bg_color
                        else:
                            # Tie or no winner - just set background if changed
                            styles = [bg_color] * len(row)
                except (ValueError, TypeError):
                    # If error, just set background if changed
                    styles = [bg_color] * len(row)
                
                return styles
            
            st.dataframe(
                display_df.style.apply(format_row, axis=1),
                use_container_width=True,
                hide_index=True
            )
            
            # Download button
            csv = filtered_df.to_csv(index=False)
            st.download_button(
                label="Download filtered data as CSV",
                data=csv,
                file_name="shorewood_games_filtered.csv",
                mime="text/csv"
            )
        else:
            st.info("No games match the selected filters.")
    else:
        st.error(f"File not found: {shorewood_file}")
        st.info("Run the analyze_games.py script to generate the comparison file.")

# Tab 2: Team Standings
with tab2:
    st.header("Wesco Team Standings")
    
    if os.path.exists(ratings_file):
        # Load ratings data
        df_ratings = pd.read_csv(ratings_file)
        
        # Load games data to calculate wins/losses
        games_file = "games_data.json"
        wins_losses = {}
        
        if os.path.exists(games_file):
            try:
                with open(games_file, 'r', encoding='utf-8') as f:
                    games = json.load(f)
                
                # Helper function to normalize team name (same as in analyze_games.py)
                def normalize_team_name(team_name):
                    if not team_name:
                        return None
                    normalized = re.sub(r"'", "", team_name.lower().strip())
                    normalized = re.sub(r"\s+", "_", normalized)
                    return normalized
                
                # Calculate wins and losses for each team
                for game in games:
                    home_team = game.get('home_team', '')
                    away_team = game.get('away_team', '')
                    home_score = game.get('home_score', '')
                    away_score = game.get('away_score', '')
                    
                    # Only count games with valid scores
                    if home_score and away_score and home_score != '' and away_score != '':
                        try:
                            home_score = float(home_score)
                            away_score = float(away_score)
                            
                            home_key = normalize_team_name(home_team)
                            away_key = normalize_team_name(away_team)
                            
                            if home_key and away_key:
                                # Initialize if needed
                                if home_key not in wins_losses:
                                    wins_losses[home_key] = {'wins': 0, 'losses': 0}
                                if away_key not in wins_losses:
                                    wins_losses[away_key] = {'wins': 0, 'losses': 0}
                                
                                # Count wins/losses
                                if home_score > away_score:
                                    wins_losses[home_key]['wins'] += 1
                                    wins_losses[away_key]['losses'] += 1
                                elif away_score > home_score:
                                    wins_losses[away_key]['wins'] += 1
                                    wins_losses[home_key]['losses'] += 1
                        except (ValueError, TypeError):
                            pass
            except Exception as e:
                st.warning(f"Could not load games data: {e}")
        
        filtered_ratings = df_ratings.copy()
        
        if len(filtered_ratings) > 0:
            # Show Shorewood's position if in the data (right before the table)
            shorewood_team = filtered_ratings[filtered_ratings['Team'].str.contains('shorewood', case=False, na=False)]
            if len(shorewood_team) > 0:
                # Determine which rating column to use
                if 'OLS_Rating' in df_ratings.columns:
                    rating_col = 'OLS_Rating'
                elif 'xMargin' in df_ratings.columns:
                    rating_col = 'xMargin'
                else:
                    rating_col = None
                
                if rating_col:
                    # Calculate rank in the full dataset (not filtered)
                    df_ratings_sorted = df_ratings.sort_values(rating_col, ascending=False).reset_index(drop=True)
                    shorewood_idx = df_ratings_sorted[df_ratings_sorted['Team'].str.contains('shorewood', case=False, na=False)].index[0]
                    shorewood_rank = shorewood_idx + 1  # Rank is 1-based
                    
                    shorewood_rating = shorewood_team.iloc[0]
                    rating_value = float(shorewood_rating[rating_col])
                    # Format rating with "+" for positive values
                    rating_display = f"+{rating_value:.1f}" if rating_value > 0 else f"{rating_value:.1f}"
                    
                    # Place metrics side by side in a compact layout
                    col1, col2, col3 = st.columns([1, 1, 2])
                    with col1:
                        st.metric("Shorewood Rank", f"#{int(shorewood_rank)}")
                    with col2:
                        st.metric("Shorewood Rating", rating_display)
                    
                    st.divider()
            
            # Format ratings for display
            display_ratings = filtered_ratings.copy()
            
            # Use OLS_Rating if available, otherwise fall back to xMargin
            if 'OLS_Rating' in display_ratings.columns:
                rating_col = 'OLS_Rating'
            elif 'xMargin' in display_ratings.columns:
                rating_col = 'xMargin'
            else:
                rating_col = None
            
            if rating_col:
                # Add wins, losses, and win percentage
                display_ratings['Wins'] = display_ratings['Team'].apply(
                    lambda x: wins_losses.get(x, {}).get('wins', 0) if x in wins_losses else 0
                )
                display_ratings['Losses'] = display_ratings['Team'].apply(
                    lambda x: wins_losses.get(x, {}).get('losses', 0) if x in wins_losses else 0
                )
                display_ratings['Win%'] = display_ratings.apply(
                    lambda row: (row['Wins'] / (row['Wins'] + row['Losses']) * 100) if (row['Wins'] + row['Losses']) > 0 else 0.0,
                    axis=1
                )
                
                # Format rating to one decimal place (keep as float for sorting and styling)
                display_ratings['Rating'] = display_ratings[rating_col].apply(
                    lambda x: float(x) if pd.notna(x) else 0.0
                )
                
                # Sort by Win% first (descending), then by Rating (descending)
                display_ratings = display_ratings.sort_values(['Win%', 'Rating'], ascending=[False, False])
                
                # Calculate min, max, and median for gradient coloring
                rating_min = display_ratings['Rating'].min()
                rating_max = display_ratings['Rating'].max()
                rating_median = display_ratings['Rating'].median()
                rating_range = rating_max - rating_min
                
                # Function to get color based on rating value
                # Using more saturated, darker colors for better visibility
                def get_rating_color(value):
                    if rating_range == 0:
                        return '#B8860B'  # Dark goldenrod if all values are the same
                    
                    if value < rating_median:
                        # Red to Dark Goldenrod (lower half)
                        # Red: rgb(220, 20, 60) -> Dark Goldenrod: rgb(184, 134, 11)
                        ratio = (value - rating_min) / (rating_median - rating_min) if rating_median > rating_min else 0
                        r = int(220 - (220 - 184) * ratio)  # 220 -> 184
                        g = int(20 + (134 - 20) * ratio)    # 20 -> 134
                        b = int(60 + (11 - 60) * ratio)     # 60 -> 11
                    else:
                        # Dark Goldenrod to Dark Green (upper half)
                        # Dark Goldenrod: rgb(184, 134, 11) -> Dark Green: rgb(0, 100, 0)
                        ratio = (value - rating_median) / (rating_max - rating_median) if rating_max > rating_median else 1
                        r = int(184 - 184 * ratio)      # 184 -> 0
                        g = int(134 + (100 - 134) * ratio)  # 134 -> 100
                        b = int(11 - 11 * ratio)        # 11 -> 0
                    
                    return f'rgb({r}, {g}, {b})'
                
                # Format columns for display
                display_ratings['Win%'] = display_ratings['Win%'].apply(lambda x: f"{x:.1f}")
                
                # Keep numeric Rating for styling, create display version
                rating_numeric = display_ratings['Rating'].copy()
                # Create a mapping of team to numeric rating for easy lookup
                team_rating_map = dict(zip(display_ratings['Team'], rating_numeric))
                
                # Format Rating as string for display
                display_ratings['Rating'] = display_ratings['Rating'].apply(lambda x: f"{x:.1f}")
                
                # Reorder columns: Team, Wins, Losses, Win%, Rating
                display_ratings = display_ratings[['Team', 'Wins', 'Losses', 'Win%', 'Rating']]
                
                # Create a styled version with bold and colored Rating column
                def style_rating_column(row):
                    styles = [''] * len(row)
                    rating_idx = list(row.index).index('Rating')
                    # Get the numeric rating value for this row using the mapping
                    team_name = row['Team']
                    team_rating = team_rating_map.get(team_name, 0.0)
                    color = get_rating_color(team_rating)
                    styles[rating_idx] = f'font-weight: bold; color: {color};'
                    return styles
                
                # Apply styling
                styled_df = display_ratings.style.apply(style_rating_column, axis=1)
                
                # Display with styling
                st.dataframe(
                    styled_df,
                    use_container_width=False,
                    hide_index=True,
                    height="content",  # Show all rows without scrolling
                    column_config={
                        "Team": st.column_config.TextColumn("Team", width="medium"),
                        "Wins": st.column_config.NumberColumn("Wins", width="small"),
                        "Losses": st.column_config.NumberColumn("Losses", width="small"),
                        "Win%": st.column_config.TextColumn("Win%", width="small"),
                        "Rating": st.column_config.TextColumn("Rating", width="small")
                    }
                )
            else:
                st.error("No rating column found in the data")
            
            # Download button - use the display format
            csv = display_ratings.to_csv(index=False)
            st.download_button(
                label="Download standings as CSV",
                data=csv,
                file_name="team_standings.csv",
                mime="text/csv"
            )
        else:
            st.info("No teams match the search term.")
    else:
        st.error(f"File not found: {ratings_file}")
        st.info("Run the analyze_games.py script to generate the ratings file.")

# Sidebar with info
with st.sidebar:
    st.header("About")
    st.write("""
    This dashboard displays:
    - **Shorewood Games**: All games for Shorewood with change tracking
    - **Team Ratings**: League-wide team ratings calculated using regularized regression
    
    Data is updated by running the `analyze_games.py` script.
    """)
    
    st.divider()
    
    st.header("Files")
    if os.path.exists(shorewood_file):
        st.success(f"✓ {shorewood_file}")
    else:
        st.error(f"✗ {shorewood_file}")
    
    if os.path.exists(ratings_file):
        st.success(f"✓ {ratings_file}")
    else:
        st.error(f"✗ {ratings_file}")

