"""
Scraper for Exposure Basketball Events website
Scrapes game scores from the Wesco Girls AAU schedule page
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException
import time
import json
import re
from datetime import datetime

def setup_driver(headless=False):
    """Set up Chrome WebDriver with appropriate options"""
    chrome_options = Options()
    if headless:
        chrome_options.add_argument('--headless')
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')
    chrome_options.add_argument('--disable-blink-features=AutomationControlled')
    chrome_options.add_argument('user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
    
    # Try to create driver (will use system ChromeDriver if available)
    try:
        driver = webdriver.Chrome(options=chrome_options)
        return driver
    except Exception as e:
        print(f"Error setting up Chrome driver: {e}")
        print("Make sure ChromeDriver is installed and in your PATH")
        raise

def get_division_id(driver, division_name="4th Girls"):
    """
    Extract the division ID from the data-bind attribute
    
    Args:
        driver: Selenium WebDriver instance
        division_name: Name of the division
    
    Returns:
        Division ID (integer) or None if not found
    """
    try:
        # Find the link containing the division name
        division_elements = driver.find_elements(By.CLASS_NAME, "display-8")
        
        for div_element in division_elements:
            if division_name in div_element.text:
                # Find the parent <a> tag
                link = div_element.find_element(By.XPATH, "./ancestor::a")
                # Get the data-bind attribute
                data_bind = link.get_attribute("data-bind")
                if data_bind:
                    # Extract the ID from "click: showDivision.bind($data, 1297521)"
                    match = re.search(r'showDivision\.bind\([^,]+,\s*(\d+)', data_bind)
                    if match:
                        division_id = int(match.group(1))
                        print(f"Found division ID: {division_id}")
                        return division_id
        return None
    except Exception as e:
        print(f"Error extracting division ID: {e}")
        return None

def click_division_link(driver, division_name="4th Girls", timeout=10):
    """
    Click on a division link (e.g., "4th Girls") to show the schedule
    
    Args:
        driver: Selenium WebDriver instance
        division_name: Name of the division to click (default: "4th Girls")
        timeout: Maximum time to wait for element (seconds)
    
    Returns:
        True if successful, False otherwise
    """
    try:
        print(f"Looking for '{division_name}' link...")
        
        wait = WebDriverWait(driver, timeout)
        
        # Strategy 1: Find by the display-8 class containing the division name
        try:
            # Wait for division links to be present
            wait.until(EC.presence_of_element_located((By.CLASS_NAME, "display-8")))
            
            # Find all elements with class "display-8" (division names)
            division_elements = driver.find_elements(By.CLASS_NAME, "display-8")
            
            target_link = None
            for div_element in division_elements:
                if division_name in div_element.text:
                    # Find the parent <a> tag
                    target_link = div_element.find_element(By.XPATH, "./ancestor::a")
                    break
            
            if target_link:
                print(f"Found '{division_name}' link")
                # Scroll into view
                driver.execute_script("arguments[0].scrollIntoView({behavior: 'smooth', block: 'center'});", target_link)
                time.sleep(0.5)
                
                # Get the division ID and trigger the JavaScript function directly
                division_id = get_division_id(driver, division_name)
                
                if division_id:
                    # Trigger the showDivision function directly via JavaScript
                    print(f"Triggering showDivision({division_id}) via JavaScript...")
                    driver.execute_script(f"if (typeof ko !== 'undefined' && ko.dataFor) {{ var element = arguments[0]; var context = ko.dataFor(element); if (context && context.showDivision) {{ context.showDivision({division_id}); }} }}", target_link)
                    time.sleep(1)
                    # Also try regular click as backup
                    try:
                        target_link.click()
                    except:
                        driver.execute_script("arguments[0].click();", target_link)
                else:
                    # Fallback to regular click
                    try:
                        target_link.click()
                    except:
                        driver.execute_script("arguments[0].click();", target_link)
                
                print(f"Clicked '{division_name}' link")
                time.sleep(3)  # Wait for content to load
                return True
            else:
                print(f"Could not find '{division_name}' link")
                # Try alternative: find by data-bind attribute
                print("Trying alternative method: searching by data-bind attribute...")
                links = driver.find_elements(By.CSS_SELECTOR, "a[data-bind*='showDivision']")
                if links:
                    print(f"Found {len(links)} division links with showDivision")
                    # Click the first one for now (you can filter by division if needed)
                    driver.execute_script("arguments[0].click();", links[0])
                    time.sleep(2)
                    return True
                return False
                
        except Exception as e:
            print(f"Error finding/clicking link: {e}")
            import traceback
            traceback.print_exc()
            return False
            
    except TimeoutException:
        print(f"Timeout waiting for '{division_name}' link")
        return False
    except Exception as e:
        print(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return False

def scrape_boxscores(driver, timeout=10):
    """
    Scrape boxscore data from the loaded page
    
    Args:
        driver: Selenium WebDriver instance
        timeout: Maximum time to wait for elements
    
    Returns:
        List of dictionaries containing game data
    """
    games = []
    
    try:
        print("Scraping boxscores...")
        
        # Wait for game cards to load
        wait = WebDriverWait(driver, timeout)
        wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, ".card")))
        time.sleep(1)  # Additional wait for dynamic content
        
        # Find all game cards - look for cards that contain card-body with team info
        # We'll filter to only cards that have the game structure
        all_cards = driver.find_elements(By.CSS_SELECTOR, ".card")
        print(f"Found {len(all_cards)} total cards")
        
        # Find all date headers first - look for divs with the date header classes
        # Using a more flexible selector that matches the key classes
        date_headers = driver.find_elements(By.CSS_SELECTOR, "div.bg-dark.text-white.mb-4")
        # Filter to only those that contain a span (the date text)
        date_headers = [h for h in date_headers if h.find_elements(By.CSS_SELECTOR, "span")]
        print(f"Found {len(date_headers)} date headers")
        
        # Create a helper function to find the date for a given element
        def find_date_for_element(element):
            """Find the most recent date header that appears before this element"""
            try:
                # Get all date headers and their positions
                date_info = []
                for header in date_headers:
                    try:
                        date_span = header.find_element(By.CSS_SELECTOR, "span")
                        date_text = date_span.text.strip()
                        # Skip if it's just an icon or empty
                        if date_text and len(date_text) > 5:  # Date should be longer than 5 chars
                            # Get the Y position of the header
                            header_y = header.location['y']
                            date_info.append((header_y, date_text, header))
                    except:
                        continue
                
                if not date_info:
                    return None
                
                # Get the Y position of the current element
                element_y = element.location['y']
                
                # Find the most recent date header that's above this element
                valid_dates = [(y, text, header) for y, text, header in date_info if y < element_y]
                if valid_dates:
                    # Sort by Y position (descending) to get the most recent one
                    valid_dates.sort(key=lambda x: x[0], reverse=True)
                    return valid_dates[0][1]  # Return the date text
                elif date_info:
                    # If no date is above, use the first date (shouldn't happen, but just in case)
                    date_info.sort(key=lambda x: x[0])
                    return date_info[0][1]
                return None
            except Exception as e:
                print(f"    Warning: Error finding date: {e}")
                return None
        
        # Filter to only cards that have game data (card-body with final-score spans)
        game_cards = []
        for card in all_cards:
            try:
                # Check if this card has the game structure we're looking for
                card_body = card.find_element(By.CSS_SELECTOR, ".card-body")
                score_spans = card_body.find_elements(By.CSS_SELECTOR, "span.final-score")
                if len(score_spans) >= 2:  # Should have at least 2 scores (away and home)
                    game_cards.append(card)
            except:
                # Not a game card, skip it
                continue
        
        print(f"Found {len(game_cards)} game cards with score data")
        
        for idx, card in enumerate(game_cards):
            try:
                game_data = {}
                
                # Find the date for this game
                game_date = find_date_for_element(card)
                if game_date:
                    game_data['date'] = game_date
                else:
                    game_data['date'] = None
                
                # Extract time and venue from card header
                try:
                    card_header = card.find_element(By.CSS_SELECTOR, ".card-header")
                    # Time is in the first div
                    time_elements = card_header.find_elements(By.CSS_SELECTOR, "div")
                    if time_elements:
                        game_data['time'] = time_elements[0].text.strip()
                    
                    # Venue and court info
                    venue_spans = card_header.find_elements(By.CSS_SELECTOR, "span")
                    if len(venue_spans) >= 2:
                        game_data['venue'] = venue_spans[0].text.strip()
                        # Court name is in parentheses
                        court_text = venue_spans[1].text.strip()
                        if '(' in court_text and ')' in court_text:
                            game_data['court'] = court_text.strip('()')
                except Exception as e:
                    print(f"  Warning: Could not extract header info: {e}")
                
                # Extract team names and scores from card body
                try:
                    card_body = card.find_element(By.CSS_SELECTOR, ".card-body")
                    
                    # Get both team divs (away is first, home is second)
                    # Use XPath to get direct children divs with class d-flex
                    team_divs = card_body.find_elements(By.XPATH, "./div[contains(@class, 'd-flex')]")
                    
                    # Alternative: if XPath doesn't work, try CSS selector for direct children
                    if len(team_divs) < 2:
                        team_divs = card_body.find_elements(By.CSS_SELECTOR, "> div.d-flex")
                    
                    # If still not found, try without the direct child requirement
                    if len(team_divs) < 2:
                        team_divs = card_body.find_elements(By.CSS_SELECTOR, "div.d-flex")
                    
                    if len(team_divs) < 2:
                        print(f"  Warning: Game {idx+1} - Expected 2 team divs, found {len(team_divs)}")
                        # Try a different approach - find by the structure
                        # Look for divs that contain a final-score span, but get the parent
                        away_div = None
                        home_div = None
                        score_spans = card_body.find_elements(By.CSS_SELECTOR, "span.final-score")
                        if len(score_spans) >= 2:
                            # Get the parent div of each score span (should be the team div)
                            for span in score_spans:
                                parent_div = span.find_element(By.XPATH, "./ancestor::div[contains(@class, 'd-flex')][1]")
                                if away_div is None:
                                    away_div = parent_div
                                elif home_div is None:
                                    home_div = parent_div
                                    break
                        
                        if away_div and home_div:
                            team_divs = [away_div, home_div]
                            print(f"    Found team divs using alternative method (via score spans)")
                        else:
                            print(f"    Could not find team divs using alternative method")
                            # Debug: show what we found in card body
                            try:
                                body_html = card_body.get_attribute('innerHTML')[:500]
                                print(f"    Card body preview: {body_html}")
                            except:
                                pass
                            continue
                    
                    # Extract away team (first div)
                    away_team_div = team_divs[0]
                    
                    # Extract away team name
                    try:
                        # First try to find the <a> tag with team name
                        away_team_link = away_team_div.find_element(By.CSS_SELECTOR, "a")
                        game_data['away_team'] = away_team_link.text.strip()
                    except NoSuchElementException:
                        # Fallback: try to get text from the text-truncate div
                        try:
                            text_div = away_team_div.find_element(By.CSS_SELECTOR, "div.text-truncate.mr-auto")
                            game_data['away_team'] = text_div.text.strip()
                        except:
                            # Last resort: get all text and clean it up
                            all_text = away_team_div.find_element(By.CSS_SELECTOR, "div.text-truncate.mr-auto").text.strip()
                            game_data['away_team'] = all_text.split('\n')[0].strip() if all_text else None
                    
                    if not game_data.get('away_team'):
                        print(f"  Warning: Could not extract away team name for game {idx+1}")
                        continue
                    
                    # Extract away score
                    try:
                        away_score_span = away_team_div.find_element(By.CSS_SELECTOR, "span.final-score")
                        away_score = away_score_span.text.strip()
                        # Filter out placeholder scores like "(A)" or "(H)"
                        if away_score and away_score not in ['(A)', '(H)', '']:
                            game_data['away_score'] = away_score
                        else:
                            game_data['away_score'] = None
                    except NoSuchElementException:
                        game_data['away_score'] = None
                    
                    # Extract home team (second div)
                    home_team_div = team_divs[1]
                    
                    # Extract home team name
                    try:
                        # First try to find the <a> tag with team name
                        home_team_link = home_team_div.find_element(By.CSS_SELECTOR, "a")
                        game_data['home_team'] = home_team_link.text.strip()
                    except NoSuchElementException:
                        # Fallback: try to get text from the text-truncate div
                        try:
                            text_div = home_team_div.find_element(By.CSS_SELECTOR, "div.text-truncate.mr-auto")
                            game_data['home_team'] = text_div.text.strip()
                        except:
                            # Last resort: get all text and clean it up
                            all_text = home_team_div.find_element(By.CSS_SELECTOR, "div.text-truncate.mr-auto").text.strip()
                            game_data['home_team'] = all_text.split('\n')[0].strip() if all_text else None
                    
                    if not game_data.get('home_team'):
                        print(f"  Warning: Could not extract home team name for game {idx+1}")
                        continue
                    
                    # Extract home score
                    try:
                        home_score_span = home_team_div.find_element(By.CSS_SELECTOR, "span.final-score")
                        home_score = home_score_span.text.strip()
                        # Filter out placeholder scores like "(A)" or "(H)"
                        if home_score and home_score not in ['(A)', '(H)', '']:
                            game_data['home_score'] = home_score
                        else:
                            game_data['home_score'] = None
                    except NoSuchElementException:
                        game_data['home_score'] = None
                        
                except Exception as e:
                    print(f"  Warning: Could not extract team/score info: {e}")
                    import traceback
                    traceback.print_exc()
                    continue
                
                # Extract division and game type from card footer
                try:
                    card_footers = card.find_elements(By.CSS_SELECTOR, ".card-footer")
                    if card_footers:
                        footer_text = card_footers[0].text.strip()
                        # Footer format: "4th Girls, Pool A" or similar
                        if ',' in footer_text:
                            parts = footer_text.split(',')
                            game_data['division'] = parts[0].strip()
                            game_data['game_type'] = parts[1].strip() if len(parts) > 1 else None
                        else:
                            game_data['division'] = footer_text
                            game_data['game_type'] = None
                except Exception as e:
                    print(f"  Warning: Could not extract footer info: {e}")
                
                # Only add game if we have both team names
                if 'away_team' in game_data and 'home_team' in game_data and game_data['away_team'] and game_data['home_team']:
                    games.append(game_data)
                    away_score_str = game_data.get('away_score', 'N/A')
                    home_score_str = game_data.get('home_score', 'N/A')
                    print(f"  Extracted: {game_data['away_team']} ({away_score_str}) vs {game_data['home_team']} ({home_score_str})")
                else:
                    print(f"  Skipped incomplete game data (missing team names)")
                    
            except Exception as e:
                print(f"  Error processing game card: {e}")
                continue
        
        # Save page source and screenshot for debugging
        page_source = driver.page_source
        with open("page_source.html", "w", encoding="utf-8") as f:
            f.write(page_source)
        driver.save_screenshot("page_screenshot.png")
        
        return games
        
    except Exception as e:
        print(f"Error scraping boxscores: {e}")
        import traceback
        traceback.print_exc()
        return games

def main():
    """Main function to orchestrate the scraping"""
    url = "https://basketball.exposureevents.com/256814/wesco-girls-aau/schedule"
    
    print("=" * 60)
    print("Exposure Basketball Events Scraper")
    print("=" * 60)
    print()
    
    driver = None
    try:
        # Setup driver (set headless=True to run without opening browser)
        print("Setting up browser...")
        driver = setup_driver(headless=False)
        
        # Navigate to the page
        print(f"Navigating to: {url}")
        driver.get(url)
        
        # Wait for page to load
        print("Waiting for page to load...")
        time.sleep(3)
        
        # Click on "4th Girls" division
        if click_division_link(driver, division_name="4th Girls"):
            print("Successfully clicked division link")
            
            # Wait for content to load
            print("Waiting for game data to load...")
            time.sleep(3)
            
            # Scrape the boxscores
            games = scrape_boxscores(driver)
            
            if games:
                print(f"\nScraped {len(games)} games")
                # Save to JSON
                with open("games_data.json", "w", encoding="utf-8") as f:
                    json.dump(games, f, indent=2)
                print("Saved game data to 'games_data.json'")
                
                # Save timestamp of when data was scraped
                timestamp_data = {
                    "last_updated": datetime.now().isoformat(),
                    "timestamp_pst": datetime.now().strftime("%A, %B %d, %Y at %I:%M %p PST")
                }
                with open("data_timestamp.json", "w", encoding="utf-8") as f:
                    json.dump(timestamp_data, f, indent=2)
                print(f"Saved timestamp: {timestamp_data['timestamp_pst']}")
            else:
                print("\nNo games found. Check 'page_source.html' and 'page_screenshot.png' to inspect the page structure.")
        else:
            print("Failed to click division link")
            
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        if driver:
            print("\nClosing browser...")
            input("Press Enter to close the browser...")  # Keep browser open for inspection
            driver.quit()
            print("Browser closed")

if __name__ == "__main__":
    main()

