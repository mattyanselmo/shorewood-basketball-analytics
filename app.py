"""
Streamlit app for Basketball Analytics
- Tab 1: Shorewood game results and comparisons
- Tab 2: League team ratings
"""

import streamlit as st
import pandas as pd
import os

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

# Check if files exist
shorewood_file = "shorewood_games_comparison.csv"
ratings_file = "team_ratings.csv"

# Create tabs
tab1, tab2 = st.tabs(["Shorewood Games", "Team Ratings"])

# Tab 1: Shorewood Games
with tab1:
    st.header("Shorewood Game Results & Comparisons")
    
    if os.path.exists(shorewood_file):
        # Load data
        df = pd.read_csv(shorewood_file)
        
        # Display summary stats
        col1, col2, col3, col4 = st.columns(4)
        
        with col1:
            st.metric("Total Games", len(df))
        
        with col2:
            changed_count = len(df[df['CHANGED'] == 'YES'])
            st.metric("Games Changed", changed_count)
        
        with col3:
            games_with_scores = len(df[(df['Home Score'].notna()) & (df['Home Score'] != '') & 
                                       (df['Away Score'].notna()) & (df['Away Score'] != '')])
            st.metric("Games with Scores", games_with_scores)
        
        with col4:
            if 'Home Team' in df.columns and 'Away Team' in df.columns:
                # Count wins (assuming Shorewood is in one of the columns)
                wins = 0
                for _, row in df.iterrows():
                    home_team = str(row.get('Home Team', ''))
                    away_team = str(row.get('Away Team', ''))
                    home_score = row.get('Home Score', '')
                    away_score = row.get('Away Score', '')
                    
                    if home_score and away_score and home_score != '' and away_score != '':
                        try:
                            home_score = float(home_score)
                            away_score = float(away_score)
                            if home_team == 'Shorewood' and home_score > away_score:
                                wins += 1
                            elif away_team == 'Shorewood' and away_score > home_score:
                                wins += 1
                        except:
                            pass
                st.metric("Shorewood Wins", wins)
        
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

# Tab 2: Team Ratings
with tab2:
    st.header("League Team Ratings")
    
    if os.path.exists(ratings_file):
        # Load data
        df_ratings = pd.read_csv(ratings_file)
        
        # Search/filter
        search_term = st.text_input("Search for a team:", "")
        
        if search_term:
            filtered_ratings = df_ratings[
                df_ratings['Team'].str.contains(search_term, case=False, na=False)
            ]
        else:
            filtered_ratings = df_ratings.copy()
        
        # Show Shorewood's position if in the data (before the table)
        shorewood_team = filtered_ratings[filtered_ratings['Team'].str.contains('shorewood', case=False, na=False)]
        if len(shorewood_team) > 0:
            # Calculate rank in the full dataset (not filtered)
            df_ratings_sorted = df_ratings.sort_values('xMargin', ascending=False).reset_index(drop=True)
            shorewood_idx = df_ratings_sorted[df_ratings_sorted['Team'].str.contains('shorewood', case=False, na=False)].index[0]
            shorewood_rank = shorewood_idx + 1  # Rank is 1-based
            
            shorewood_rating = shorewood_team.iloc[0]
            col1, col2 = st.columns(2)
            with col1:
                st.metric("Shorewood Rank", f"#{int(shorewood_rank)}")
            with col2:
                st.metric("Shorewood Rating", f"{float(shorewood_rating['xMargin']):.1f}")
            
            st.divider()
        
        if len(filtered_ratings) > 0:
            # Format ratings for display
            display_ratings = filtered_ratings.copy()
            
            # Format xMargin to one decimal place
            if 'xMargin' in display_ratings.columns:
                display_ratings['xMargin'] = display_ratings['xMargin'].apply(
                    lambda x: f"{float(x):.1f}" if pd.notna(x) else ""
                )
            
            # Add ranking (based on full dataset, not filtered)
            # First, get ranks from full sorted dataset
            df_ratings_sorted = df_ratings.sort_values('xMargin', ascending=False).reset_index(drop=True)
            df_ratings_sorted['Rank'] = range(1, len(df_ratings_sorted) + 1)
            
            # Merge ranks back to filtered results
            display_ratings = display_ratings.merge(
                df_ratings_sorted[['Team', 'Rank']],
                on='Team',
                how='left'
            )
            
            # Reorder columns to put Rank first
            cols = ['Rank'] + [col for col in display_ratings.columns if col != 'Rank']
            display_ratings = display_ratings[cols]
            
            # Sort by rank
            display_ratings = display_ratings.sort_values('Rank')
            
            # Display without background color formatting
            st.dataframe(
                display_ratings,
                use_container_width=True,
                hide_index=True
            )
            
            # Download button
            csv = filtered_ratings.to_csv(index=False)
            st.download_button(
                label="Download ratings as CSV",
                data=csv,
                file_name="team_ratings_filtered.csv",
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

