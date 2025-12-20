# Test script to click "4th Girls" link and extract box scores
# Uses Selenium to handle JavaScript-rendered content

# Load required libraries
if (!require("RSelenium")) install.packages("RSelenium")
if (!require("rvest")) install.packages("rvest")
if (!require("httr")) install.packages("httr")
if (!require("wdman")) install.packages("wdman")

library(RSelenium)
library(rvest)
library(httr)
library(wdman)

# Configuration: Set to TRUE to use local browser (visible), FALSE for Docker (headless)
USE_LOCAL_BROWSER <- TRUE  # Change to FALSE to use Docker

# Track which driver method was used (for cleanup)
rD_server <- NULL  # Will store rsDriver server if used
used_system_chromedriver <- FALSE  # Track if we used system ChromeDriver

# URL
url <- "https://basketball.exposureevents.com/256814/wesco-girls-aau/schedule"

cat("=== Basketball Box Score Scraper Test ===\n\n")

# Setup Selenium
cat("1. Setting up Selenium connection...\n")

if (USE_LOCAL_BROWSER) {
  cat("   Using LOCAL browser (you'll see the browser window)\n")
  
  # Helper function to fix macOS Gatekeeper issue for ChromeDriver
  fix_gatekeeper_if_needed <- function(chromedriver_path) {
    # Check if file has quarantine attribute (Gatekeeper)
    quarantine_check <- system(paste0("xattr -l '", chromedriver_path, "' 2>&1"), 
                              intern = TRUE, ignore.stderr = TRUE)
    if (any(grepl("com.apple.quarantine", quarantine_check))) {
      cat("   ChromeDriver is quarantined by macOS Gatekeeper\n")
      cat("   Attempting to remove quarantine attribute...\n")
      system(paste0("xattr -d com.apple.quarantine '", chromedriver_path, "' 2>&1"), 
            ignore.stdout = TRUE, ignore.stderr = TRUE)
      cat("   ✓ Quarantine attribute removed\n")
      return(TRUE)
    }
    return(FALSE)
  }
  
  # Helper function to detect Chrome version
  detect_chrome_version <- function() {
    chrome_paths <- c(
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "C:/Program Files/Google/Chrome/Application/chrome.exe",
      "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
      "/usr/bin/google-chrome",
      "/usr/bin/chromium-browser"
    )
    
    for (chrome_path in chrome_paths) {
      if (file.exists(chrome_path)) {
        # Try to get version using --version flag
        version_output <- tryCatch({
          system2(chrome_path, args = "--version", stdout = TRUE, stderr = TRUE)
        }, error = function(e) NULL)
        
        if (!is.null(version_output) && length(version_output) > 0) {
          # Extract version number (e.g., "Google Chrome 143.0.7499.110")
          version_match <- regmatches(version_output, regexpr("\\d+\\.\\d+\\.\\d+\\.\\d+", version_output))
          if (length(version_match) > 0) {
            major_version <- as.numeric(strsplit(version_match[1], "\\.")[[1]][1])
            return(list(version = version_match[1], major = major_version, path = chrome_path))
          }
        }
      }
    }
    return(NULL)
  }
  
  # Detect Chrome version
  cat("   Detecting Chrome version...\n")
  chrome_info <- detect_chrome_version()
  if (!is.null(chrome_info)) {
    cat(sprintf("   Found Chrome version: %s (major: %d)\n", chrome_info$version, chrome_info$major))
  } else {
    cat("   Could not detect Chrome version automatically\n")
  }
  
  # Clear wdman cache to prevent using old ChromeDriver versions
  cat("   Clearing wdman cache to prevent version conflicts...\n")
  cache_dir <- path.expand("~/Library/Application Support/binman_chromedriver")
  if (dir.exists(cache_dir)) {
    unlink(cache_dir, recursive = TRUE)
    cat("   ✓ wdman cache cleared\n")
  } else {
    cat("   ✓ No wdman cache found\n")
  }
  
  # Helper function to kill existing ChromeDriver processes and free port
  cleanup_existing_chromedriver <- function(port = 4567L) {
    cat("   Cleaning up any existing ChromeDriver processes...\n")
    # Kill ALL ChromeDriver processes (not just on specific port)
    system("pkill -9 -f chromedriver 2>/dev/null", ignore.stdout = TRUE, ignore.stderr = TRUE)
    # Also kill any processes using the port
    system(sprintf("lsof -ti:%d 2>/dev/null | xargs kill -9 2>/dev/null", port), 
           ignore.stdout = TRUE, ignore.stderr = TRUE)
    # Wait a bit longer to ensure processes are fully terminated
    Sys.sleep(2)
    cat("   ✓ Cleanup complete\n")
  }
  
  # Method 1: Use system-installed ChromeDriver (most reliable if installed via brew)
  cat("   Method 1: Trying system-installed ChromeDriver (via brew)...\n")
  remDr <- NULL
  rD_server <- NULL
  
  tryCatch({
    # Clean up any existing ChromeDriver processes first
    cleanup_existing_chromedriver(4567L)
    
    # Check if chromedriver is in PATH
    chromedriver_check <- system("which chromedriver 2>/dev/null", intern = TRUE)
    if (length(chromedriver_check) > 0 && nchar(chromedriver_check[1]) > 0) {
      chromedriver_path <- chromedriver_check[1]
      cat(sprintf("   Found ChromeDriver at: %s\n", chromedriver_path))
      
      # Fix Gatekeeper issue if needed
      fix_gatekeeper_if_needed(chromedriver_path)
      
      # Check if ChromeDriver can run and verify version
      cat("   Testing ChromeDriver...\n")
      test_result <- tryCatch({
        system(paste0(chromedriver_path, " --version 2>&1"), 
               intern = TRUE, ignore.stderr = TRUE)
      }, error = function(e) NULL)
      
      if (!is.null(test_result) && length(test_result) > 0) {
        version_line <- paste(test_result, collapse = " ")
          if (grepl("ChromeDriver", version_line)) {
            # Extract version number (e.g., "143.0.7499.42")
            version_match <- regmatches(version_line, regexpr("\\d+\\.\\d+\\.\\d+\\.\\d+", version_line))
            if (length(version_match) > 0) {
              driver_version <- version_match[1]
              driver_major <- as.numeric(strsplit(driver_version, "\\.")[[1]][1])
              cat(sprintf("   ✓ ChromeDriver version: %s (major: %d)\n", driver_version, driver_major))
              # Check if version matches Chrome major version
              if (!is.null(chrome_info) && chrome_info$major > 0) {
                if (abs(driver_major - chrome_info$major) > 5) {
                  cat(sprintf("   ⚠ Warning: ChromeDriver major version (%d) may not match Chrome version (%d)\n", 
                             driver_major, chrome_info$major))
                } else {
                  cat(sprintf("   ✓ ChromeDriver version matches Chrome version (both major %d)\n", driver_major))
                }
              }
            } else {
              cat("   ✓ ChromeDriver is accessible\n")
            }
        } else {
          cat("   ⚠ ChromeDriver test failed, but will try anyway\n")
        }
      } else {
        cat("   ⚠ ChromeDriver test failed, but will try anyway\n")
        cat("   If it fails, you may need to allow it in System Settings > Privacy & Security\n")
      }
      
      # Start ChromeDriver manually in background with explicit path
      cat("   Starting ChromeDriver on port 4567...\n")
      # Use system2 for better control, or construct command properly
      # On macOS, we need to properly background the process
      cmd <- sprintf("%s --port=4567", chromedriver_path)
      # Use system2 with stdout/stderr redirection and background execution
      system2(chromedriver_path, args = c("--port=4567"), 
              stdout = "/dev/null", stderr = "/dev/null", wait = FALSE)
      Sys.sleep(5)  # Give it more time to start
      
      # Verify ChromeDriver started successfully
      port_check <- tryCatch({
        system(sprintf("lsof -ti:4567 2>/dev/null"), intern = TRUE)
      }, error = function(e) character(0))
      
      if (length(port_check) > 0 && nchar(port_check[1]) > 0) {
        cat("   ✓ ChromeDriver started successfully on port 4567\n")
      } else {
        # Try one more time with a different approach
        cat("   Port check failed, trying alternative start method...\n")
        # Try using nohup or direct background execution
        system(paste0("nohup ", chromedriver_path, " --port=4567 > /dev/null 2>&1 &"), 
               ignore.stdout = TRUE, ignore.stderr = TRUE)
        Sys.sleep(3)
        port_check2 <- tryCatch({
          system(sprintf("lsof -ti:4567 2>/dev/null"), intern = TRUE)
        }, error = function(e) character(0))
        if (length(port_check2) > 0 && nchar(port_check2[1]) > 0) {
          cat("   ✓ ChromeDriver started successfully on port 4567 (alternative method)\n")
        } else {
          stop("ChromeDriver failed to start on port 4567")
        }
      }
      
      used_system_chromedriver <<- TRUE  # Mark that we used system ChromeDriver
      
      # Connect to it
      remDr <<- remoteDriver(remoteServerAddr = "localhost", 
                            port = 4567L, 
                            browserName = "chrome",
                            extraCapabilities = list(chromeOptions = list(
                              args = c("--no-sandbox", "--disable-dev-shm-usage")
                            )))
      remDr$open()
      cat("   ✓ Connected using system ChromeDriver - browser window should be visible\n\n")
    } else {
      stop("ChromeDriver not found in PATH. Install with: brew install chromedriver")
    }
  }, error = function(e) {
    cat(sprintf("   ⚠ System ChromeDriver method failed: %s\n", e$message))
    cat("   Method 2: Trying with wdman ChromeDriver...\n")
    
    # Method 2: Use wdman with manual ChromeDriver management
    tryCatch({
      # Clean up first
      cleanup_existing_chromedriver(4567L)
      
      # First, try to use system ChromeDriver if available (better than downloading)
      chromedriver_check <- system("which chromedriver 2>/dev/null", intern = TRUE)
      if (length(chromedriver_check) > 0 && nchar(chromedriver_check[1]) > 0) {
        chromedriver_path <- chromedriver_check[1]
        cat("   Found system ChromeDriver, using it directly instead of wdman...\n")
        # Use system ChromeDriver directly
        system2(chromedriver_path, args = c("--port=4567"), 
                stdout = "/dev/null", stderr = "/dev/null", wait = FALSE)
        Sys.sleep(5)
        chrome_driver <<- list(process = "system_chromedriver")  # Dummy object for cleanup
        used_system_chromedriver <<- TRUE
        cat("   ✓ System ChromeDriver started via wdman fallback\n")
      } else {
        # Clear wdman cache to force download of correct version
        cat("   Clearing wdman cache to ensure correct ChromeDriver version...\n")
        cache_dir <- path.expand("~/Library/Application Support/binman_chromedriver")
        if (dir.exists(cache_dir)) {
          unlink(cache_dir, recursive = TRUE)
          cat("   ✓ Cache cleared\n")
        }
        
        # Try to start ChromeDriver with explicit version if we detected Chrome version
        cat("   Downloading/starting ChromeDriver via wdman...\n")
        if (!is.null(chrome_info) && chrome_info$major > 0) {
          # Try to use a version close to Chrome's major version
          # wdman expects version strings like "114.0.5735.90" or "LATEST"
          cat(sprintf("   Attempting to use ChromeDriver version matching Chrome %d...\n", chrome_info$major))
          # Try LATEST first, which should get a recent version
          chrome_driver <<- chrome(port = 4567L, 
                                  verbose = TRUE, 
                                  chromever = "LATEST")  # Use LATEST instead of check=TRUE
        } else {
          chrome_driver <<- chrome(port = 4567L, 
                                  verbose = TRUE, 
                                  check = TRUE)
        }
        Sys.sleep(5)  # Give it more time
        cat("   ✓ ChromeDriver started via wdman\n")
      }
      
      # Connect to ChromeDriver
      remDr <<- remoteDriver(remoteServerAddr = "localhost", 
                            port = 4567L, 
                            browserName = "chrome",
                            extraCapabilities = list(chromeOptions = list(
                              args = c("--no-sandbox", "--disable-dev-shm-usage")
                            )))
      remDr$open()
      cat("   ✓ Connected - browser window should be visible\n\n")
    }, error = function(e2) {
      cat(sprintf("   ⚠ wdman method failed: %s\n", e2$message))
      cat("   Method 3: Trying rsDriver (may download dependencies)...\n")
      
      # Method 3: Use rsDriver (last resort - may have issues with phantomjs downloads)
      tryCatch({
        # rsDriver handles ChromeDriver version matching automatically
        # Note: This may try to download phantomjs which is deprecated
        rD <- rsDriver(browser = "chrome", 
                      port = 4567L, 
                      chromever = "latest",
                      verbose = FALSE,  # Less verbose to avoid phantomjs warnings
                      check = FALSE)  # Skip check to avoid version issues
        remDr <<- rD[["client"]]
        rD_server <<- rD[["server"]]  # Store server for cleanup
        cat("   ✓ Connected using rsDriver - browser window should be visible\n\n")
      }, error = function(e3) {
        cat(sprintf("   ⚠ rsDriver method failed: %s\n", e3$message))
        cat("\n   === All methods failed ===\n")
        cat("   Troubleshooting steps:\n")
        cat("   1. If ChromeDriver is blocked by macOS Gatekeeper:\n")
        cat("      - Go to System Settings > Privacy & Security\n")
        cat("      - Allow ChromeDriver to run\n")
        cat("      - Or run: xattr -d com.apple.quarantine $(which chromedriver)\n")
        cat("   2. Install/update ChromeDriver:\n")
        cat("      brew install chromedriver\n")
        cat("   3. Update R packages:\n")
        cat("      install.packages(c('RSelenium', 'wdman'), repos = 'https://cran.r-project.org')\n")
        cat("   4. Use Docker mode by setting USE_LOCAL_BROWSER <- FALSE\n\n")
        stop("Could not start Chrome browser. All methods failed:\n",
             "  Method 1 (system): ", e$message, "\n",
             "  Method 2 (wdman): ", e2$message, "\n",
             "  Method 3 (rsDriver): ", e3$message)
      })
    })
  })
  
} else {
  cat("   Using DOCKER (headless browser)\n")
  
  # Use Docker setup
  remDr <- remoteDriver(remoteServerAddr = "localhost", 
                        port = 4444L, 
                        browserName = "chrome")
  
  # Check if Selenium is ready
  cat("   Checking if Selenium server is ready...\n")
  status_url <- "http://localhost:4444/wd/hub/status"
  tryCatch({
    response <- httr::GET(status_url, timeout = httr::timeout(3))
    if (httr::status_code(response) == 200) {
      cat("   ✓ Selenium server is ready\n")
    } else {
      stop("Selenium server returned non-200 status")
    }
  }, error = function(e) {
    stop("Could not connect to Selenium server. Make sure Docker container is running:\n",
         "  docker ps\n",
         "  If not running: docker run -d -p 4444:4444 selenium/standalone-chrome")
  })
  
  # Connect to Selenium
  cat("2. Connecting to Selenium...\n")
  remDr$open()
  cat("   ✓ Connected\n\n")
}

tryCatch({
  # Navigate to the page
  cat("3. Navigating to schedule page...\n")
  remDr$navigate(url)
  
  # Wait for page to load and verify
  cat("   Waiting for page to load...\n")
  Sys.sleep(5)  # Initial wait
  
  # Verify we're on the right page
  tryCatch({
    current_url <- remDr$getCurrentUrl()[[1]]
    cat(sprintf("   Current URL: %s\n", current_url))
  }, error = function(e) {
    cat("   Could not get current URL\n")
  })
  
  # Wait for body or specific elements to appear
  cat("   Waiting for page elements to load...\n")
  max_wait <- 10
  page_ready <- FALSE
  for (i in 1:max_wait) {
    tryCatch({
      # Try to find body or a specific element that should be on the page
      body <- remDr$findElement(using = "tag name", "body")
      if (!is.null(body)) {
        # Check if we can find any content
        body_text <- body$getElementText()[[1]]
        if (nchar(body_text) > 100) {
          page_ready <- TRUE
          cat(sprintf("   ✓ Page appears ready (waited %d seconds)\n", i))
          break
        }
      }
    }, error = function(e) {
      # Continue waiting
    })
    if (i < max_wait) {
      Sys.sleep(1)
    }
  }
  
  if (!page_ready) {
    cat("   ⚠ Page may not be fully loaded, proceeding anyway...\n")
  }
  cat("\n")
  
  # Click the "4th Girls" link
  cat("4. Clicking '4th Girls' link...\n")
  
  # Wait a bit more for dynamic content
  Sys.sleep(3)
  
  link_clicked <- FALSE
  last_error <- NULL
  
  # Strategy 1: Use CSS selector with data-bind attribute (most reliable - unique identifier)
  tryCatch({
    cat("   Trying CSS selector with data-bind attribute...\n")
    link_element <- remDr$findElement(using = "css", 
                                       value = "a[data-bind*='showDivision.bind($data, 1297521)']")
    # Use JavaScript click (more reliable for href="#")
    remDr$executeScript("arguments[0].click();", list(link_element))
    cat("   ✓ Clicked '4th Girls' link (CSS + data-bind + JS click)\n\n")
    link_clicked <- TRUE
  }, error = function(e) {
    last_error <<- e$message
    cat("   CSS data-bind selector failed, trying other methods...\n")
  })
  
  # Strategy 2: Use JavaScript to find and click directly
  if (!link_clicked) {
    tryCatch({
      cat("   Trying JavaScript querySelector...\n")
      remDr$executeScript("document.querySelector(\"a[data-bind*='showDivision.bind($data, 1297521)']\").click();")
      cat("   ✓ Clicked '4th Girls' link (JavaScript querySelector)\n\n")
      link_clicked <- TRUE
    }, error = function(e) {
      last_error <<- e$message
      cat("   JavaScript querySelector failed...\n")
    })
  }
  
  # Strategy 3: Find by class and filter in R
  if (!link_clicked) {
    tryCatch({
      cat("   Trying CSS class selector and filtering...\n")
      elements <- remDr$findElements(using = "css", value = "a.btn-light.border-gray-darken")
      cat(sprintf("   Found %d elements with btn-light class\n", length(elements)))
      
      if (length(elements) > 0) {
        # Filter to find the one with "4th Girls" text
        for (i in seq_along(elements)) {
          tryCatch({
            elem_text <- elements[[i]]$getElementText()[[1]]
            if (grepl("4th Girls", elem_text, ignore.case = TRUE)) {
              # Use JavaScript click
              remDr$executeScript("arguments[0].click();", list(elements[[i]]))
              cat(sprintf("   ✓ Clicked '4th Girls' link (found at position %d via class filter)\n\n", i))
              link_clicked <- TRUE
              break
            }
          }, error = function(e) {
            # Skip this element
          })
        }
      }
    }, error = function(e) {
      last_error <<- e$message
      cat("   Class selector + filter failed...\n")
    })
  }
  
  # Strategy 4: Fallback to XPath with JavaScript click
  if (!link_clicked) {
    tryCatch({
      cat("   Trying XPath with JavaScript click...\n")
      link_element <- remDr$findElement(using = "xpath", 
                                         value = "//a[.//div[contains(text(), '4th Girls')]]")
      remDr$executeScript("arguments[0].click();", list(link_element))
      cat("   ✓ Clicked '4th Girls' link (XPath + JS click)\n\n")
      link_clicked <- TRUE
    }, error = function(e) {
      last_error <<- e$message
      cat("   XPath + JS click failed...\n")
    })
  }
  
  # Strategy 5: Try regular click as last resort
  if (!link_clicked) {
    tryCatch({
      cat("   Trying regular click as last resort...\n")
      link_element <- remDr$findElement(using = "css", 
                                         value = "a[data-bind*='showDivision.bind($data, 1297521)']")
      link_element$clickElement()
      cat("   ✓ Clicked '4th Girls' link (regular click)\n\n")
      link_clicked <- TRUE
    }, error = function(e) {
      last_error <<- e$message
      cat("   Regular click failed...\n")
    })
  }
  
  # Strategy 6: Debug - show what's on the page
  if (!link_clicked) {
    cat("\n   === DEBUG: Page Status ===\n")
    
    # Check current URL
    tryCatch({
      current_url <- remDr$getCurrentUrl()[[1]]
      cat(sprintf("   Current URL: %s\n", current_url))
    }, error = function(e) {
      cat("   Could not get current URL\n")
    })
    
    # Check page title
    tryCatch({
      page_title <- remDr$getTitle()[[1]]
      cat(sprintf("   Page title: %s\n", page_title))
    }, error = function(e) {
      cat("   Could not get page title\n")
    })
    
    # Check body content
    tryCatch({
      body <- remDr$findElement(using = "tag name", "body")
      body_text <- body$getElementText()[[1]]
      cat(sprintf("   Body text length: %d characters\n", nchar(body_text)))
      if (nchar(body_text) > 0) {
        cat(sprintf("   First 200 chars: %s\n", substr(body_text, 1, 200)))
      }
    }, error = function(e) {
      cat(sprintf("   Could not get body text: %s\n", e$message))
    })
    
    # Try to find links
    cat("\n   === Looking for links ===\n")
    tryCatch({
      all_links <- remDr$findElements(using = "xpath", "//a")
      cat(sprintf("   Found %d total links on page\n", length(all_links)))
      if (length(all_links) > 0) {
        for (i in seq_len(min(20, length(all_links)))) {
          tryCatch({
            link_text <- all_links[[i]]$getElementText()[[1]]
            if (nchar(link_text) > 0 && nchar(link_text) < 100) {
              cat(sprintf("   [%d] %s\n", i, substr(link_text, 1, 50)))
            }
          }, error = function(e) {
            # Skip
          })
        }
      }
    }, error = function(e) {
      cat(sprintf("   Could not retrieve links: %s\n", e$message))
    })
    
    # Try to find divs with "Girls" text
    cat("\n   === Looking for 'Girls' elements ===\n")
    tryCatch({
      girls_elements <- remDr$findElements(using = "xpath", "//*[contains(text(), 'Girls')]")
      cat(sprintf("   Found %d elements containing 'Girls'\n", length(girls_elements)))
      if (length(girls_elements) > 0) {
        for (i in seq_len(min(10, length(girls_elements)))) {
          tryCatch({
            elem_text <- girls_elements[[i]]$getElementText()[[1]]
            if (nchar(elem_text) > 0 && nchar(elem_text) < 100) {
              cat(sprintf("   [%d] %s\n", i, substr(elem_text, 1, 50)))
            }
          }, error = function(e) {
            # Skip
          })
        }
      }
    }, error = function(e) {
      cat(sprintf("   Could not find 'Girls' elements: %s\n", e$message))
    })
    
    # Try to get page source
    cat("\n   === Attempting to save page source ===\n")
    tryCatch({
      page_source_result <- remDr$getPageSource()
      if (is.list(page_source_result)) {
        if (length(page_source_result) > 0) {
          page_source_debug <- page_source_result[[1]]
        } else {
          page_source_debug <- paste(page_source_result, collapse = "\n")
        }
      } else if (is.character(page_source_result)) {
        page_source_debug <- page_source_result
      } else {
        page_source_debug <- as.character(page_source_result)
      }
      
      if (nchar(page_source_debug) > 0) {
        writeLines(page_source_debug, "debug_page_before_click.html")
        cat("   ✓ Page source saved to 'debug_page_before_click.html'\n")
      } else {
        cat("   ✗ Page source is empty\n")
      }
    }, error = function(e) {
      cat(sprintf("   ✗ Error getting page source: %s\n", e$message))
    })
    
    cat("\n")
    stop("Could not find or click '4th Girls' link. Last error: ", last_error)
  }
  
  # Wait for the schedule/games to load (AJAX/SPA content)
  cat("5. Waiting for games/schedule content to load (AJAX)...\n")
  Sys.sleep(2)  # Initial wait for JavaScript to start
  
  # Use explicit waits to check for content that appears after the click
  max_wait <- 15
  content_loaded <- FALSE
  target_elements <- NULL
  
  for (i in 1:max_wait) {
    tryCatch({
      # Look for indicators that the schedule content has loaded:
      # 1. Game cards with team names
      # 2. "No scheduled games" message
      # 3. Schedule section that appears after clicking
      
      # Try multiple selectors to find the loaded content
      game_cards <- remDr$findElements(using = "css", value = "div.card")
      team_links <- remDr$findElements(using = "css", value = "a[data-bind*='TeamName']")
      no_games_msg <- remDr$findElements(using = "xpath", value = "//div[contains(text(), 'No scheduled games')]")
      schedule_section <- remDr$findElements(using = "css", value = "div[data-bind*='gamesViewModel']")
      
      # If we find any of these, content has loaded
      if (length(game_cards) > 0 || length(team_links) > 0 || length(no_games_msg) > 0 || length(schedule_section) > 0) {
        content_loaded <- TRUE
        cat(sprintf("   ✓ Content loaded! Found: %d cards, %d team links (waited %d seconds)\n", 
                    length(game_cards), length(team_links), i))
        
        # Store the elements we found for later extraction
        target_elements <- list(
          game_cards = game_cards,
          team_links = team_links,
          no_games_msg = no_games_msg
        )
        break
      }
    }, error = function(e) {
      # Continue waiting
    })
    
    if (i < max_wait) {
      Sys.sleep(1)
      if (i %% 3 == 0) {
        cat(sprintf("   Still waiting for content... (%d/%d seconds)\n", i, max_wait))
      }
    }
  }
  
  if (!content_loaded) {
    cat("   ⚠ Content may not have loaded, but proceeding anyway...\n")
  }
  cat("\n")
  
  # Verify browser is still connected
  cat("5b. Verifying browser connection...\n")
  tryCatch({
    current_url <- remDr$getCurrentUrl()[[1]]
    cat(sprintf("   ✓ Browser connected, current URL: %s\n", current_url))
    
    page_title <- remDr$getTitle()[[1]]
    cat(sprintf("   ✓ Page title: %s\n", page_title))
    cat("\n")
  }, error = function(e) {
    cat(sprintf("   ✗ Browser connection issue: %s\n", e$message))
    cat("\n")
  })
  
  # Extract page content - try direct extraction first, then page source as fallback
  cat("6. Extracting page content...\n")
  Sys.sleep(10)
  # Strategy: If we found elements directly, extract from them first
  # Only use getPageSource() if we need the full HTML
  page <- NULL
  page_source <- NULL
  
  if (content_loaded && !is.null(target_elements) && length(target_elements$team_links) > 0) {
    cat("   Content found via direct element search - will extract directly from elements\n")
    cat("   (Skipping getPageSource() since we can extract from found elements)\n\n")
    
    # We'll extract directly from elements in step 7
    # For now, just note that we have the elements
  } else {
    cat("   Attempting to get full page source...\n")
  tryCatch({
    cat("   Method 1: Trying getPageSource()...\n")
    page_source_result <- remDr$getPageSource()
    
    cat(sprintf("   DEBUG: getPageSource() returned type: %s\n", class(page_source_result)[1]))
    cat(sprintf("   DEBUG: Length: %d\n", length(page_source_result)))
    
    # Handle different return formats
    if (is.list(page_source_result)) {
      cat(sprintf("   DEBUG: It's a list with %d elements\n", length(page_source_result)))
      if (length(page_source_result) > 0) {
        page_source <- page_source_result[[1]]
        cat(sprintf("   DEBUG: Extracted first element, type: %s, length: %d\n", 
                    class(page_source)[1], length(page_source)))
      } else {
        # Empty list - try to convert
        page_source <- paste(page_source_result, collapse = "\n")
        cat("   DEBUG: Empty list, converted to string\n")
      }
    } else if (is.character(page_source_result)) {
      page_source <- page_source_result
      cat(sprintf("   DEBUG: It's a character vector, length: %d\n", length(page_source)))
    } else {
      # Try to convert to character
      page_source <- as.character(page_source_result)
      if (length(page_source) > 1) {
        page_source <- paste(page_source, collapse = "\n")
      }
      cat(sprintf("   DEBUG: Converted to character, length: %d\n", length(page_source)))
    }
    
    # Show what we got
    if (!is.null(page_source)) {
      page_source_len <- if (is.character(page_source)) nchar(page_source[1]) else 0
      cat(sprintf("   DEBUG: Final page_source length: %d characters\n", page_source_len))
      if (page_source_len > 0 && page_source_len < 500) {
        cat(sprintf("   DEBUG: First 200 chars: %s\n", substr(page_source[1], 1, 200)))
      }
    }
    
    # Verify we have valid HTML
    if (is.null(page_source) || length(page_source) == 0) {
      stop("Page source is NULL or empty")
    }
    
    page_source_char <- if (is.character(page_source)) page_source[1] else as.character(page_source)[1]
    if (nchar(page_source_char) < 100) {
      stop(sprintf("Page source is too short: %d characters", nchar(page_source_char)))
    }
    
    page <- read_html(page_source_char)
    cat("   ✓ Page source extracted\n\n")
  }, error = function(e) {
    cat(sprintf("   ✗ Error getting page source: %s\n", e$message))
    cat("   Attempting alternative method...\n")
    
    # Try alternative: get page source via JavaScript
    tryCatch({
      cat("   Method 2: Trying JavaScript document.documentElement.outerHTML...\n")
      js_result <- remDr$executeScript("return document.documentElement.outerHTML;")
      
      cat(sprintf("   DEBUG: executeScript() returned type: %s\n", class(js_result)[1]))
      cat(sprintf("   DEBUG: Length: %d\n", length(js_result)))
      
      # Handle different return formats from executeScript
      if (is.list(js_result)) {
        cat(sprintf("   DEBUG: It's a list with %d elements\n", length(js_result)))
        if (length(js_result) > 0) {
          page_source <- js_result[[1]]
        } else {
          page_source <- paste(js_result, collapse = "\n")
        }
      } else if (is.character(js_result)) {
        page_source <- js_result
        cat(sprintf("   DEBUG: It's a character vector, length: %d\n", length(page_source)))
      } else {
        page_source <- as.character(js_result)
        if (length(page_source) > 1) {
          page_source <- paste(page_source, collapse = "\n")
        }
        cat(sprintf("   DEBUG: Converted to character, length: %d\n", length(page_source)))
      }
      
      page_source_char <- if (is.character(page_source)) page_source[1] else as.character(page_source)[1]
      page_source_len <- nchar(page_source_char)
      cat(sprintf("   DEBUG: Final page_source length: %d characters\n", page_source_len))
      if (page_source_len > 0 && page_source_len < 500) {
        cat(sprintf("   DEBUG: First 200 chars: %s\n", substr(page_source_char, 1, 200)))
      }
      
      if (is.null(page_source) || length(page_source) == 0) {
        stop("JavaScript method returned NULL or empty")
      }
      
      if (page_source_len < 100) {
        stop(sprintf("JavaScript method returned too short page source: %d characters", page_source_len))
      }
      
      page <- read_html(page_source_char)
      cat("   ✓ Page source extracted via JavaScript\n\n")
    }, error = function(e2) {
      cat(sprintf("   ✗ JavaScript method also failed: %s\n", e2$message))
      cat("   Trying one more method: getting body HTML...\n")
      
      # Last resort: try getting body HTML
      tryCatch({
        cat("   Method 3: Trying JavaScript document.body.innerHTML...\n")
        body_result <- remDr$executeScript("return document.body.innerHTML;")
        
        cat(sprintf("   DEBUG: executeScript() returned type: %s\n", class(body_result)[1]))
        cat(sprintf("   DEBUG: Length: %d\n", length(body_result)))
        
        if (is.list(body_result) && length(body_result) > 0) {
          body_html <- body_result[[1]]
          cat(sprintf("   DEBUG: Extracted first element from list\n"))
        } else if (is.character(body_result)) {
          body_html <- body_result
          cat(sprintf("   DEBUG: It's a character vector\n"))
        } else {
          body_html <- as.character(body_result)
          if (length(body_html) > 1) {
            body_html <- paste(body_html, collapse = "\n")
          }
          cat(sprintf("   DEBUG: Converted to character\n"))
        }
        
        body_html_char <- if (is.character(body_html)) body_html[1] else as.character(body_html)[1]
        body_html_len <- if (!is.na(body_html_char) && nchar(body_html_char) > 0) nchar(body_html_char) else 0
        cat(sprintf("   DEBUG: Body HTML length: %d characters\n", body_html_len))
        if (body_html_len > 0 && body_html_len < 500) {
          cat(sprintf("   DEBUG: First 200 chars: %s\n", substr(body_html_char, 1, 200)))
        }
        
        if (is.null(body_html) || length(body_html) == 0) {
          stop("Body HTML is NULL or empty")
        }
        
        if (body_html_len < 100) {
          stop(sprintf("Body HTML is too short: %d characters", body_html_len))
        }
        
        # Wrap in basic HTML structure
        page_source <- paste0("<!DOCTYPE html><html><body>", body_html_char, "</body></html>")
        page <- read_html(page_source)
        cat("   ✓ Page source extracted via body HTML\n\n")
      }, error = function(e3) {
        cat(sprintf("   ✗ Body HTML method also failed: %s\n", e3$message))
        cat("   Trying final method: using body element we already found...\n")
        
        # Final fallback: use the body element we found earlier
        tryCatch({
          if (!is.null(body_element)) {
            cat("   Method 4: Getting outerHTML from body element...\n")
            body_outer_html <- body_element$getElementAttribute("outerHTML")[[1]]
            
            if (!is.null(body_outer_html) && nchar(body_outer_html) > 100) {
              # Wrap in basic HTML structure
              page_source <- paste0("<!DOCTYPE html><html>", body_outer_html, "</html>")
              page <- read_html(page_source)
              cat("   ✓ Page source extracted via body element outerHTML\n\n")
            } else {
              stop("Body outerHTML is NULL or too short")
            }
          } else {
            stop("Body element not available")
          }
        }, error = function(e4) {
          cat(sprintf("   ✗ Body element method also failed: %s\n", e4$message))
          cat("\n   === SUMMARY OF ALL FAILED METHODS ===\n")
          cat("   Method 1 (getPageSource): ", e$message, "\n")
          cat("   Method 2 (JS outerHTML): ", e2$message, "\n")
          cat("   Method 3 (JS innerHTML): ", e3$message, "\n")
          cat("   Method 4 (body element): ", e4$message, "\n")
          cat("\n   The browser may have closed or the page may not be accessible.\n")
          cat("   Try checking if the browser window is still open.\n")
          stop("Failed to get page source with all methods")
        })
      })
    })
  })
  }  # Close the else block
  
  # Extract box scores/game data
  cat("7. Extracting box scores...\n\n")
  
  games_data <- list()
  
  # Strategy 1: Extract directly from Selenium elements (if we found them)
  if (content_loaded && !is.null(target_elements) && length(target_elements$game_cards) > 0) {
    cat("   Extracting directly from Selenium elements...\n")
    game_cards_selenium <- target_elements$game_cards
    
    cat(sprintf("   Found %d game card(s) via Selenium\n\n", length(game_cards_selenium)))
    
    for (i in seq_along(game_cards_selenium)) {
      card <- game_cards_selenium[[i]]
      
      tryCatch({
        # Get the card's HTML to parse with rvest
        card_html <- card$getElementAttribute("outerHTML")[[1]]
        card_page <- read_html(card_html)
        
        # Extract team names and scores
        away_team_link <- card_page %>% html_nodes(xpath = ".//a[contains(@data-bind, 'AwayTeamName')]")
        away_team_name <- if (length(away_team_link) > 0) {
          away_team_link[[1]] %>% html_text(trim = TRUE)
        } else {
          NA_character_
        }
        
        away_score_spans <- card_page %>% html_nodes(xpath = ".//span[@class='final-score']")
        away_score <- if (length(away_score_spans) >= 1) {
          away_score_spans[[1]] %>% html_text(trim = TRUE)
        } else {
          NA_character_
        }
        
        home_team_link <- card_page %>% html_nodes(xpath = ".//a[contains(@data-bind, 'HomeTeamName')]")
        home_team_name <- if (length(home_team_link) > 0) {
          home_team_link[[1]] %>% html_text(trim = TRUE)
        } else {
          NA_character_
        }
        
        home_score <- if (length(away_score_spans) >= 2) {
          away_score_spans[[2]] %>% html_text(trim = TRUE)
        } else {
          NA_character_
        }
        
        # Only add if we found team names
        if (!is.na(away_team_name) && !is.na(home_team_name)) {
          games_data[[length(games_data) + 1]] <- list(
            game_number = length(games_data) + 1,
            away_team = away_team_name,
            away_score = away_score,
            home_team = home_team_name,
            home_score = home_score
          )
          
          cat(sprintf("--- Game %d ---\n", length(games_data)))
          cat(sprintf("Away: %s (%s)\n", away_team_name, ifelse(is.na(away_score), "TBD", away_score)))
          cat(sprintf("Home: %s (%s)\n", home_team_name, ifelse(is.na(home_score), "TBD", home_score)))
          cat("\n")
        }
      }, error = function(e) {
        # Skip this card if there's an error
      })
    }
  }
  
  # Strategy 2: Extract from page source (if we have it)
  if (length(games_data) == 0 && !is.null(page)) {
    cat("   Extracting from page source (rvest)...\n")
    
    # Look for game cards in the page source
    game_cards <- page %>% html_nodes(xpath = "//div[@class='card']")
    cat(sprintf("   Found %d card(s) in page source\n\n", length(game_cards)))
    
    for (i in seq_along(game_cards)) {
      card <- game_cards[[i]]
      
      # Extract team names and scores
      away_team_link <- card %>% html_nodes(xpath = ".//a[contains(@data-bind, 'AwayTeamName')]")
      away_team_name <- if (length(away_team_link) > 0) {
        away_team_link[[1]] %>% html_text(trim = TRUE)
      } else {
        NA_character_
      }
      
      away_score_spans <- card %>% html_nodes(xpath = ".//span[@class='final-score']")
      away_score <- if (length(away_score_spans) >= 1) {
        away_score_spans[[1]] %>% html_text(trim = TRUE)
      } else {
        NA_character_
      }
      
      home_team_link <- card %>% html_nodes(xpath = ".//a[contains(@data-bind, 'HomeTeamName')]")
      home_team_name <- if (length(home_team_link) > 0) {
        home_team_link[[1]] %>% html_text(trim = TRUE)
      } else {
        NA_character_
      }
      
      home_score <- if (length(away_score_spans) >= 2) {
        away_score_spans[[2]] %>% html_text(trim = TRUE)
      } else {
        NA_character_
      }
      
      # Only add if we found team names
      if (!is.na(away_team_name) && !is.na(home_team_name)) {
        games_data[[length(games_data) + 1]] <- list(
          game_number = length(games_data) + 1,
          away_team = away_team_name,
          away_score = away_score,
          home_team = home_team_name,
          home_score = home_score
        )
        
        cat(sprintf("--- Game %d ---\n", length(games_data)))
        cat(sprintf("Away: %s (%s)\n", away_team_name, ifelse(is.na(away_score), "TBD", away_score)))
        cat(sprintf("Home: %s (%s)\n", home_team_name, ifelse(is.na(home_score), "TBD", home_score)))
        cat("\n")
      }
    }
  }
  
  # Strategy 3: Try finding elements again if we haven't found anything
  if (length(games_data) == 0) {
    cat("   Trying to find game elements again...\n")
    tryCatch({
      # Find all game cards again
      game_cards_fresh <- remDr$findElements(using = "css", value = "div.card")
      
      if (length(game_cards_fresh) > 0) {
        cat(sprintf("   Found %d game card(s) on retry\n\n", length(game_cards_fresh)))
        
        for (i in seq_along(game_cards_fresh)) {
          card <- game_cards_fresh[[i]]
          
          tryCatch({
            # Try to get text directly from the card
            card_text <- card$getElementText()[[1]]
            
            # Look for team names in the text (simple pattern matching)
            # This is a fallback if HTML parsing doesn't work
            if (grepl("\\d+", card_text) && nchar(card_text) > 20) {
              cat(sprintf("   Card %d text: %s\n", i, substr(card_text, 1, 100)))
            }
          }, error = function(e) {
            # Skip
          })
        }
      }
    }, error = function(e) {
      cat(sprintf("   Could not find game elements: %s\n", e$message))
    })
  }
  
  if (length(games_data) > 0) {
    cat(sprintf("=== Successfully extracted %d game(s) ===\n\n", length(games_data)))
    
    # Convert to data frame for easier viewing
    games_df <- do.call(rbind, lapply(games_data, function(x) {
      data.frame(
        game_number = x$game_number,
        away_team = x$away_team,
        away_score = x$away_score,
        home_team = x$home_team,
        home_score = x$home_score,
        stringsAsFactors = FALSE
      )
    }))
    
    print(games_df)
    cat("\n")
    
    # Save to files
    saveRDS(games_data, "extracted_games.rds")
    write.csv(games_df, "extracted_games.csv", row.names = FALSE)
    cat("Game data saved to:\n")
    cat("  - extracted_games.rds (R format)\n")
    cat("  - extracted_games.csv (CSV format)\n\n")
    
  } else {
    cat("No games found with team names.\n")
    cat("This might mean:\n")
    cat("  - No games are scheduled yet\n")
    cat("  - Games haven't loaded (JavaScript issue)\n")
    cat("  - The page structure is different than expected\n\n")
  }
  
  # Also try the specific XPath for box scores (if we have page source)
  if (!is.null(page)) {
    cat("8. Checking target box score XPath...\n")
    cat("   XPath: /html/body/div[3]/div/div/div[4]/div[4]/div[4]/div/div[2]/div[2]/div[1]/div\n")
    
    box_score_div <- page %>% html_nodes(xpath = "/html/body/div[3]/div/div/div[4]/div[4]/div[4]/div/div[2]/div[2]/div[1]/div")
    
    if (length(box_score_div) > 0) {
      cat(sprintf("   ✓ Found %d element(s) at target XPath\n\n", length(box_score_div)))
      
      cat("=== BOX SCORE DIV CONTENT ===\n")
      for (i in seq_along(box_score_div)) {
        text_content <- box_score_div[[i]] %>% html_text(trim = TRUE)
        html_content <- box_score_div[[i]] %>% as.character()
        
        cat(sprintf("--- Element %d ---\n", i))
        cat("Text:", text_content, "\n")
        cat("HTML (first 1000 chars):\n", substr(html_content, 1, 1000), "\n\n")
      }
    } else {
      cat("   ✗ No element found at that XPath\n\n")
    }
  } else {
    cat("8. Skipping XPath check (no page source available)\n\n")
  }
  
  # Save the full page HTML for inspection (if we have it)
  if (!is.null(page_source) && nchar(page_source) > 0) {
    writeLines(page_source, "test_page_after_click.html")
    cat("Full page HTML saved to 'test_page_after_click.html' for inspection\n\n")
  }
  
}, finally = {
  # Close browser
  cat("9. Closing browser...\n")
  tryCatch({
    remDr$close()
    cat("   ✓ Browser closed\n")
  }, error = function(e) {
    cat(sprintf("   ⚠ Error closing browser: %s\n", e$message))
  })
  
  # Stop ChromeDriver/rsDriver server if using local browser
  if (USE_LOCAL_BROWSER) {
    # Stop rsDriver server if we used that method
    if (!is.null(rD_server)) {
      tryCatch({
        rD_server$stop()
        cat("   ✓ rsDriver server stopped\n")
      }, error = function(e) {
        cat(sprintf("   ⚠ Error stopping rsDriver server: %s\n", e$message))
      })
    }
    
    # Stop wdman ChromeDriver if we used that method
    if (exists("chrome_driver")) {
      tryCatch({
        chrome_driver$stop()
        cat("   ✓ ChromeDriver stopped\n")
      }, error = function(e) {
        cat(sprintf("   ⚠ Error stopping ChromeDriver: %s\n", e$message))
      })
    }
    
    # Stop system ChromeDriver if we used that method
    if (exists("used_system_chromedriver") && used_system_chromedriver) {
      tryCatch({
        # Find and kill ChromeDriver process on port 4567
        system("pkill -f 'chromedriver --port=4567'", ignore.stdout = TRUE, ignore.stderr = TRUE)
        cat("   ✓ System ChromeDriver stopped\n")
      }, error = function(e) {
        cat(sprintf("   ⚠ Error stopping system ChromeDriver: %s\n", e$message))
        cat("   You may need to manually stop ChromeDriver: pkill chromedriver\n")
      })
    }
  }
  
  cat("\n=== Test Complete ===\n")
})
