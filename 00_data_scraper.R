# Basketball League Schedule and Score Scraper
# Scrapes schedule and scores from Wesco Girls AAU basketball league
# Website: https://basketball.exposureevents.com/256814/wesco-girls-aau/schedule
#
# SETUP INSTRUCTIONS:
# 1. Install required R packages (if not already installed):
#    install.packages(c("RSelenium", "rvest", "xml2", "dplyr", "stringr", "wdman"))
#
# 2. Set up Selenium/ChromeDriver (choose one method):
#    Option A - Using Docker (recommended):
#      docker run -d -p 4444:4444 selenium/standalone-chrome
#
#    Option B - Using wdman (automatic):
#      The script will attempt to use wdman to manage ChromeDriver automatically
#
#    Option C - Manual ChromeDriver:
#      Download ChromeDriver from https://chromedriver.chromium.org/
#      Ensure it's in your PATH or specify the path in the script
#
# 3. Run the scraper:
#    source("00_data_scraper.R")
#    results <- scrape_basketball_schedule()
#
# 4. Extract box scores:
#    box_scores <- extract_box_scores(results$page_html)
#
# The script will:
# - Navigate to the schedule page
# - Click on the "4th Girls" link
# - Extract schedule and score data
# - Save the HTML page to "schedule_page.html" for inspection
# - Return structured data including games, box scores, and page elements

# Load required libraries
if (!require("RSelenium")) install.packages("RSelenium")
if (!require("rvest")) install.packages("rvest")
if (!require("xml2")) install.packages("xml2")
if (!require("dplyr")) install.packages("dplyr")
if (!require("stringr")) install.packages("stringr")
if (!require("wdman")) install.packages("wdman")
if (!require("httr")) install.packages("httr")

library(RSelenium)
library(rvest)
library(xml2)
library(dplyr)
library(stringr)
library(wdman)
library(httr)

# Helper function to check and start Docker container
ensure_docker_container <- function(container_name = "selenium-standalone-chrome", 
                                     image = NULL,
                                     port = 4444L) {
  cat("Checking Docker setup...\n")
  
  # Check if Docker is installed
  docker_check <- system("command -v docker", ignore.stdout = TRUE, ignore.stderr = TRUE)
  if (docker_check != 0) {
    stop("Docker is not installed. Please install Docker Desktop from https://www.docker.com/products/docker-desktop/")
  }
  
  # Check if Docker daemon is running
  docker_daemon_check <- system("docker info", ignore.stdout = TRUE, ignore.stderr = TRUE)
  if (docker_daemon_check != 0) {
    stop("Docker daemon is not running. Please start Docker Desktop and try again.")
  }
  
  cat("Docker is installed and running.\n")
  
  # Detect platform and choose appropriate image
  if (is.null(image)) {
    # Detect system architecture
    sys_arch <- Sys.info()["machine"]
    docker_arch <- system("docker version --format '{{.Server.Arch}}'", intern = TRUE)
    
    cat(sprintf("System architecture: %s, Docker architecture: %s\n", sys_arch, docker_arch))
    
    # For Apple Silicon (ARM64) or ARM architecture, use seleniarm image
    # Otherwise use standard selenium image with platform specification
    if (grepl("arm|aarch64", sys_arch, ignore.case = TRUE) || 
        grepl("arm|aarch64", docker_arch, ignore.case = TRUE)) {
      image <- "seleniarm/standalone-chromium"
      cat("Detected ARM architecture. Using seleniarm/standalone-chromium image.\n")
    } else {
      # For Intel/x86_64, use standard image
      image <- "selenium/standalone-chrome"
      cat("Detected x86_64 architecture. Using selenium/standalone-chrome image.\n")
    }
  }
  
  # Check if container is already running
  running_containers <- system("docker ps --format '{{.Names}}'", intern = TRUE)
  if (any(grepl(container_name, running_containers))) {
    cat(sprintf("Container '%s' is already running (skipping startup wait).\n", container_name))
    return(list(ready = TRUE, was_already_running = TRUE))
  }
  
  # Check if container exists but is stopped
  all_containers <- system("docker ps -a --format '{{.Names}}'", intern = TRUE)
  if (any(grepl(container_name, all_containers))) {
    cat(sprintf("Found existing container '%s'. Starting it...\n", container_name))
    start_result <- system(sprintf("docker start %s", container_name), 
                          ignore.stdout = TRUE, ignore.stderr = TRUE)
    if (start_result == 0) {
      cat("Container started successfully (was stopped, now running).\n")
      Sys.sleep(3)  # Wait for container to be ready
      return(list(ready = TRUE, was_already_running = FALSE))
    } else {
      cat("Failed to start existing container. Creating new one...\n")
    }
  }
  
  # Check if port is already in use
  port_check <- system(sprintf("lsof -i :%d", port), ignore.stdout = TRUE, ignore.stderr = TRUE)
  if (port_check == 0) {
    # Port is in use - might be another Selenium instance
    cat(sprintf("Port %d is already in use. Attempting to use existing service...\n", port))
    return(list(ready = TRUE, was_already_running = TRUE))
  }
  
  # Create and start new container
  cat(sprintf("Starting new Docker container '%s' with image '%s'...\n", container_name, image))
  docker_cmd <- sprintf(
    "docker run -d --name %s -p %d:4444 %s",
    container_name, port, image
  )
  
  create_result <- system(docker_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
  
  if (create_result != 0) {
    # Get error output
    error_output <- system(docker_cmd, intern = TRUE)
    
    # If ARM image failed and we're on ARM, try x86_64 emulation as fallback
    if (grepl("arm|aarch64", image, ignore.case = TRUE) && 
        grepl("no matching manifest|platform", paste(error_output, collapse = " "), ignore.case = TRUE)) {
      cat("ARM image not available. Trying x86_64 emulation mode...\n")
      fallback_image <- "selenium/standalone-chrome"
      docker_cmd <- sprintf(
        "docker run -d --name %s --platform linux/amd64 -p %d:4444 %s",
        container_name, port, fallback_image
      )
      create_result <- system(docker_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
      
      if (create_result == 0) {
        cat("Successfully started container using x86_64 emulation.\n")
        image <- fallback_image  # Update image variable for reference
      } else {
        # Try without specifying name
        cat("Failed with custom name. Trying with auto-generated name...\n")
        docker_cmd <- sprintf("docker run -d --platform linux/amd64 -p %d:4444 %s", port, fallback_image)
        create_result <- system(docker_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
      }
    } else {
      # Try without specifying name (let Docker generate one)
      cat("Failed with custom name. Trying with auto-generated name...\n")
      docker_cmd <- sprintf("docker run -d -p %d:4444 %s", port, image)
      create_result <- system(docker_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
    }
    
    if (create_result != 0) {
      error_msg <- system(docker_cmd, intern = TRUE)
      stop("Failed to start Docker container. Error output:\n", 
           paste(error_msg, collapse = "\n"),
           "\n\nTroubleshooting tips:\n",
           "1. Make sure Docker Desktop is running\n",
           "2. Try pulling the image manually: docker pull ", image, "\n",
           "3. For Apple Silicon, the script will try seleniarm/standalone-chromium or x86_64 emulation")
    }
  }
  
  cat("Waiting for container to be ready (this may take 10-20 seconds)...\n")
  Sys.sleep(10)  # Wait for Selenium to start (longer for first-time setup)
  
  # Verify container is running
  running_check <- system(sprintf("docker ps --format '{{.Names}}' | grep -q %s", container_name),
                         ignore.stdout = TRUE, ignore.stderr = TRUE)
  if (running_check != 0) {
    # Check if any container is using the port
    port_containers <- system("docker ps --format '{{.Names}}'", intern = TRUE)
    if (length(port_containers) > 0) {
      cat("Container appears to be running (checking by port usage).\n")
      return(TRUE)
    } else {
      stop("Container was created but is not running. Check Docker logs with: docker logs <container_name>")
    }
  }
  
  cat("Docker container is ready!\n")
  return(list(ready = TRUE, was_already_running = FALSE))
}

# Helper function to check if Selenium server is ready
check_selenium_ready <- function(port = 4444L, max_wait = 60, quick_check = FALSE) {
  if (quick_check) {
    cat("Quick check if Selenium server is ready...\n")
    max_wait <- 5  # Much shorter wait for already-running containers
  } else {
    cat(sprintf("Checking if Selenium server is ready (this may take up to %d seconds)...\n", max_wait))
  }
  
  start_time <- Sys.time()
  check_count <- 0
  check_interval <- if (quick_check) 1 else 2  # Check every 1 second for quick check, 2 for normal
  
  while (as.numeric(Sys.time() - start_time) < max_wait) {
    check_count <- check_count + 1
    
    # Try to connect to the Selenium status endpoint
    status_url <- sprintf("http://localhost:%d/wd/hub/status", port)
    
    tryCatch({
      response <- httr::GET(status_url, timeout = httr::timeout(2))
      if (httr::status_code(response) == 200) {
        elapsed <- round(as.numeric(Sys.time() - start_time), 1)
        if (quick_check && elapsed < 1) {
          cat("✓ Selenium server is ready!\n")
        } else {
          cat(sprintf("✓ Selenium server is ready! (took %.1f seconds)\n", elapsed))
        }
        return(TRUE)
      }
    }, error = function(e) {
      # Server not ready yet, continue waiting
    })
    
    elapsed <- round(as.numeric(Sys.time() - start_time), 1)
    if (!quick_check && check_count %% 3 == 0) {  # Print every 3rd check to avoid spam
      cat(sprintf("  Still waiting... (%.1f seconds elapsed, checking every %d seconds)\n", elapsed, check_interval))
    }
    Sys.sleep(check_interval)
  }
  
  if (!quick_check) {
    elapsed <- round(as.numeric(Sys.time() - start_time), 1)
    cat(sprintf("⚠ Warning: Selenium server health check timed out after %.1f seconds.\n", elapsed))
    cat("  The server may still be starting. Proceeding with connection attempt...\n")
  }
  return(FALSE)
}

# Function to setup Selenium driver
setup_selenium <- function(use_docker = FALSE) {
  cat("Setting up Selenium driver...\n")
  
  # Option 1: Use Docker (if specified or if local connection fails)
  if (use_docker) {
    cat("Using Docker mode...\n")
    
    # Ensure Docker container is running
    container_status <- NULL
    tryCatch({
      container_status <- ensure_docker_container()
    }, error = function(e) {
      stop("Docker setup failed: ", e$message)
    })
    
    # Check if Selenium server is ready before connecting
    # If container was already running, do a quick check; otherwise do full check
    was_already_running <- if (is.list(container_status)) {
      container_status$was_already_running
    } else {
      FALSE
    }
    
    if (was_already_running) {
      cat("Container was already running, doing quick health check...\n")
      check_selenium_ready(port = 4444L, max_wait = 5, quick_check = TRUE)
    } else {
      cat("Container was just started, waiting for Selenium server to be ready...\n")
      check_selenium_ready(port = 4444L, max_wait = 30, quick_check = FALSE)
    }
    
    # Connect to Docker Selenium server
    cat("Connecting to Docker Selenium server...\n")
    remDr <- remoteDriver(remoteServerAddr = "localhost", 
                          port = 4444L, 
                          browserName = "chrome",
                          extraCapabilities = list(
                            "goog:chromeOptions" = list(
                              args = c("--no-sandbox", "--disable-dev-shm-usage")
                            )
                          ))
    
    # Try to connect with retries and timeout
    max_retries <- 3
    last_error <- NULL
    
    for (i in 1:max_retries) {
      cat(sprintf("Connection attempt %d/%d...\n", i, max_retries))
      
      # Use a timeout for the connection attempt
      connection_result <- tryCatch({
        # Set a timeout by using system timeout or wrapping in a try with timeout
        remDr$open(silent = FALSE)
        TRUE
      }, error = function(e) {
        last_error <<- e$message
        cat(sprintf("Connection attempt %d failed: %s\n", i, e$message))
        FALSE
      })
      
      if (connection_result) {
        cat("Successfully connected to Docker Selenium server!\n")
        return(remDr)
      }
      
      if (i < max_retries) {
        cat(sprintf("Waiting 3 seconds before retry...\n"))
        Sys.sleep(3)
      }
    }
    
    # If we get here, all retries failed
    cat("\n=== Connection Failed ===\n")
    cat("Could not connect to Docker Selenium server after ", max_retries, " attempts.\n")
    cat("Last error: ", last_error, "\n\n")
    cat("Troubleshooting steps:\n")
    cat("1. Check if container is running: docker ps\n")
    cat("2. Check container logs: docker logs selenium-standalone-chrome\n")
    cat("3. Check if port 4444 is accessible: curl http://localhost:4444/wd/hub/status\n")
    cat("4. Try restarting the container: docker restart selenium-standalone-chrome\n")
    stop("Connection to Selenium server failed. See troubleshooting steps above.")
  }
  
  # Option 2: Try to connect to existing Selenium server first
  tryCatch({
    remDr <- remoteDriver(remoteServerAddr = "localhost", 
                          port = 4444L, 
                          browserName = "chrome")
    remDr$open()
    cat("Connected to existing Selenium server\n")
    return(remDr)
  }, error = function(e) {
    cat("No existing Selenium server found.\n")
    cat("Trying to start ChromeDriver using wdman...\n")
    
    # Option 3: Use wdman to manage ChromeDriver
    tryCatch({
      # Check if ChromeDriver is already managed in global environment
      if (!exists("chrome_driver", envir = .GlobalEnv)) {
        cat("Starting ChromeDriver using wdman...\n")
        chrome_driver <- wdman::chrome(port = 4567L, verbose = FALSE)
        assign("chrome_driver", chrome_driver, envir = .GlobalEnv)
        Sys.sleep(3)  # Give it time to start
      } else {
        chrome_driver <- get("chrome_driver", envir = .GlobalEnv)
        cat("Using existing ChromeDriver instance\n")
      }
      
      remDr <- remoteDriver(remoteServerAddr = "localhost", 
                            port = 4567L, 
                            browserName = "chrome")
      remDr$open()
      cat("Successfully started ChromeDriver using wdman\n")
      return(remDr)
    }, error = function(e2) {
      cat("\n=== Selenium Setup Failed ===\n")
      cat("Please choose one of these options:\n\n")
      cat("Option 1 - Docker (recommended):\n")
      cat("  docker run -d -p 4444:4444 selenium/standalone-chrome\n")
      cat("  Then run: scrape_basketball_schedule(use_docker = TRUE)\n\n")
      cat("Option 2 - Install ChromeDriver manually:\n")
      cat("  brew install chromedriver  # on macOS\n")
      cat("  Then ensure it's in your PATH\n\n")
      cat("Option 3 - Use wdman (automatic):\n")
      cat("  The script will attempt this automatically, but Chrome must be installed\n\n")
      stop("Could not start Selenium. See instructions above.")
    })
  })
}

# Main scraping function
scrape_basketball_schedule <- function(url = "https://basketball.exposureevents.com/256814/wesco-girls-aau/schedule", 
                                       use_docker = FALSE) {
  
  # Setup Selenium
  remDr <- setup_selenium(use_docker = use_docker)
  
  tryCatch({
    # Navigate to the website
    cat("Navigating to website...\n")
    remDr$navigate(url)
    
    # Wait for page to load
    Sys.sleep(3)
    
    # Find and click the "4th Girls" link
    cat("Looking for 4th Girls link...\n")
    
    # Wait a bit more for dynamic content to load
    Sys.sleep(2)
    
    # Try multiple strategies to find the link
    link_clicked <- FALSE
    
    # Strategy 1: Use the exact XPath provided by user
    tryCatch({
      cat("Trying exact XPath...\n")
      element <- remDr$findElement(using = "xpath", 
                                    value = "/html/body/div[3]/div/div/div[4]/div[3]/div/div[1]/a")
      element$clickElement()
      cat("✓ Clicked 4th Girls link using exact XPath\n")
      link_clicked <- TRUE
    }, error = function(e) {
      cat("Exact XPath failed, trying other methods...\n")
    })
    
    if (!link_clicked) {
      # Strategy 2: Find by data-bind attribute (most reliable for this site)
      tryCatch({
        cat("Trying data-bind attribute...\n")
        element <- remDr$findElement(using = "xpath", 
                                      value = "//a[@data-bind and contains(., '4th Girls')]")
        element$clickElement()
        cat("✓ Clicked 4th Girls link using data-bind attribute\n")
        link_clicked <- TRUE
      }, error = function(e) {
        cat("Data-bind method failed, trying nested text search...\n")
      })
    }
    
    if (!link_clicked) {
      # Strategy 3: Find by nested text (text is in a div inside the link)
      tryCatch({
        cat("Trying nested text search...\n")
        element <- remDr$findElement(using = "xpath", 
                                      value = "//a[.//div[contains(text(), '4th Girls')]]")
        element$clickElement()
        cat("✓ Clicked 4th Girls link using nested text search\n")
        link_clicked <- TRUE
      }, error = function(e) {
        cat("Nested text search failed, trying class-based search...\n")
      })
    }
    
    if (!link_clicked) {
      # Strategy 4: Find by class and containing "4th Girls" text
      tryCatch({
        cat("Trying class-based search...\n")
        element <- remDr$findElement(using = "xpath", 
                                      value = "//a[contains(@class, 'btn') and contains(., '4th Girls')]")
        element$clickElement()
        cat("✓ Clicked 4th Girls link using class-based search\n")
        link_clicked <- TRUE
      }, error = function(e) {
        cat("Class-based search failed, trying to find all Girls links...\n")
      })
    }
    
    if (!link_clicked) {
      # Strategy 5: Find all links containing "Girls" and click the 4th one
      tryCatch({
        cat("Trying to find all Girls links and select the 4th...\n")
        links <- remDr$findElements(using = "xpath", 
                                     value = "//a[contains(., 'Girls')]")
        cat(sprintf("Found %d links containing 'Girls'\n", length(links)))
        
        if (length(links) >= 4) {
          # Try to find the one with "4th Girls" specifically
          for (i in seq_along(links)) {
            tryCatch({
              link_text <- links[[i]]$getElementText()[[1]]
              if (grepl("4th Girls", link_text, ignore.case = TRUE)) {
                links[[i]]$clickElement()
                cat(sprintf("✓ Clicked 4th Girls link (found at position %d)\n", i))
                link_clicked <- TRUE
                break
              }
            }, error = function(e) {
              # Skip this link
            })
          }
          
          # If we didn't find "4th Girls" specifically, click the 4th one
          if (!link_clicked && length(links) >= 4) {
            links[[4]]$clickElement()
            cat("✓ Clicked 4th Girls link (4th link in list)\n")
            link_clicked <- TRUE
          }
        }
      }, error = function(e) {
        cat("Failed to find Girls links\n")
      })
    }
    
    if (!link_clicked) {
      # Debug: Print what links are available
      cat("\n=== Debug: Available links ===\n")
      tryCatch({
        all_links <- remDr$findElements(using = "xpath", "//a")
        cat(sprintf("Found %d total links on page\n", length(all_links)))
        for (i in seq_len(min(10, length(all_links)))) {
          tryCatch({
            link_text <- all_links[[i]]$getElementText()[[1]]
            if (nchar(link_text) > 0 && nchar(link_text) < 100) {
              cat(sprintf("  Link %d: %s\n", i, substr(link_text, 1, 50)))
            }
          }, error = function(e) {})
        }
      }, error = function(e) {
        cat("Could not retrieve link information\n")
      })
      
      stop("Could not find or click 4th Girls link. See debug output above.")
    }
    
    # Wait for the schedule page to load
    cat("Waiting for schedule page to load...\n")
    Sys.sleep(5)
    
    # Get the page source
    page_source <- remDr$getPageSource()[[1]]
    page <- read_html(page_source)
    
    # Extract schedule and scores
    cat("Extracting schedule and scores...\n")
    
    # Get the current URL to verify we're on the right page
    current_url <- remDr$getCurrentUrl()[[1]]
    cat("Current URL:", current_url, "\n")
    
    # Wait a bit more for any dynamic content to load
    Sys.sleep(2)
    
    # Refresh page source after potential dynamic loading
    page_source <- remDr$getPageSource()[[1]]
    page <- read_html(page_source)
    
    # Extract using the specific XPath pattern for box scores
    # The example XPath: /html/body/div[3]/div/div/div[4]/div[4]/div[4]/div/div[2]/div[2]/div[1]/div
    # This suggests a deeply nested structure
    
    # Method 1: Try the exact XPath pattern structure (adjusting indices)
    # Look for divs that match the nested pattern
    # The pattern has many nested divs, so we'll search for the structure
    tryCatch({
      # Try to find the body > div[3] structure
      body_divs <- page %>% html_nodes("body > div")
      if (length(body_divs) >= 3) {
        cat(sprintf("Found body with %d top-level divs\n", length(body_divs)))
        
        # Navigate through the nested structure
        # This is a flexible approach that tries different paths
        nested_divs <- body_divs[[3]] %>%
          html_nodes("div")
        
        cat(sprintf("Found %d nested divs in body > div[3]\n", length(nested_divs)))
      }
    }, error = function(e) {
      cat("Note: Could not parse exact XPath structure:", e$message, "\n")
    })
    
    # Method 2: Look for schedule/game containers using class names
    schedule_elements <- page %>%
      html_nodes(xpath = "//div[contains(@class, 'schedule') or contains(@class, 'game') or contains(@class, 'score') or contains(@class, 'match')]")
    
    cat(sprintf("Found %d schedule/game elements by class\n", length(schedule_elements)))
    
    # Method 3: Look for table rows (common in schedule displays)
    game_rows <- page %>%
      html_nodes("tr")
    
    cat(sprintf("Found %d table rows\n", length(game_rows)))
    
    # Method 4: Extract all divs and filter for potential box scores
    all_divs <- page %>% html_nodes("div")
    
    # Look for divs with text that might indicate game information
    # (dates, team names, scores, etc.)
    potential_game_divs <- list()
    for (i in seq_along(all_divs)) {
      div_text <- all_divs[[i]] %>% html_text(trim = TRUE)
      
      # Check if div contains game-like information
      if (nchar(div_text) > 0 && nchar(div_text) < 500) {
        # Look for patterns like dates, scores, team names
        if (grepl("\\d{1,2}/\\d{1,2}|\\d{1,2}:\\d{2}|vs\\.|@|\\d+-\\d+", div_text, ignore.case = TRUE)) {
          potential_game_divs[[length(potential_game_divs) + 1]] <- list(
            text = div_text,
            html = all_divs[[i]] %>% as.character()
          )
        }
      }
    }
    
    cat(sprintf("Found %d potential game divs by content pattern\n", length(potential_game_divs)))
    
    # Method 5: Try to find the specific box score structure
    # Based on the XPath: /html/body/div[3]/div/div/div[4]/div[4]/div[4]/div/div[2]/div[2]/div[1]/div
    # We'll try to navigate this structure
    tryCatch({
      # Build XPath step by step
      xpath_steps <- c(
        "/html/body/div[3]",
        "/html/body/div[3]/div",
        "/html/body/div[3]/div/div",
        "/html/body/div[3]/div/div/div[4]",
        "/html/body/div[3]/div/div/div[4]/div[4]",
        "/html/body/div[3]/div/div/div[4]/div[4]/div[4]"
      )
      
      for (xpath in xpath_steps) {
        elements <- page %>% html_nodes(xpath = xpath)
        if (length(elements) > 0) {
          cat(sprintf("XPath '%s' found %d elements\n", xpath, length(elements)))
        }
      }
      
      # Try the full path or a variation
      box_score_xpath <- "//div[contains(@class, 'box') or contains(@class, 'score')]//div"
      box_scores <- page %>% html_nodes(xpath = box_score_xpath)
      cat(sprintf("Found %d box score divs using XPath\n", length(box_scores)))
      
    }, error = function(e) {
      cat("Error with XPath extraction:", e$message, "\n")
    })
    
    # Extract structured game data
    games <- extract_game_data(page, remDr)
    
    # Save the HTML for inspection
    writeLines(page_source, "schedule_page.html")
    cat("Saved page HTML to schedule_page.html for inspection\n")
    
    # Return the page source and parsed data
    return(list(
      page_source = page_source,
      page_html = page,
      current_url = current_url,
      games = games,
      potential_game_divs = potential_game_divs,
      schedule_elements = length(schedule_elements),
      game_rows = length(game_rows)
    ))
    
  }, finally = {
    # Close the browser
    remDr$close()
    cat("Browser closed\n")
  })
}

# Function to extract structured game data
extract_game_data <- function(page_html, remDr) {
  games <- data.frame()
  
  # Try multiple methods to extract game information
  cat("Extracting structured game data...\n")
  
  # Method 1: Look for table-based schedules
  tryCatch({
    tables <- page_html %>% html_nodes("table")
    if (length(tables) > 0) {
      for (i in seq_along(tables)) {
        table_data <- tables[[i]] %>% html_table(fill = TRUE)
        if (length(table_data) > 0 && nrow(table_data[[1]]) > 0) {
          cat(sprintf("Found table %d with %d rows\n", i, nrow(table_data[[1]])))
          # Add to games data frame if it looks like game data
          if (any(grepl("team|score|date|time", names(table_data[[1]]), ignore.case = TRUE))) {
            games <- rbind(games, table_data[[1]])
          }
        }
      }
    }
  }, error = function(e) {
    cat("Error extracting tables:", e$message, "\n")
  })
  
  # Method 2: Use Selenium to find elements by their visible text or structure
  tryCatch({
    # Look for elements that might contain game information
    game_elements <- remDr$findElements(using = "xpath", 
                                         value = "//div[contains(@class, 'game') or contains(@class, 'schedule')]")
    
    if (length(game_elements) > 0) {
      cat(sprintf("Found %d game elements via Selenium\n", length(game_elements)))
      
      for (i in seq_along(game_elements)) {
        tryCatch({
          element_text <- game_elements[[i]]$getElementText()[[1]]
          if (nchar(element_text) > 0) {
            # Try to parse the text for game information
            # This is a basic parser - may need refinement based on actual format
            cat(sprintf("Game element %d: %s\n", i, substr(element_text, 1, 100)))
          }
        }, error = function(e) {
          # Skip this element
        })
      }
    }
  }, error = function(e) {
    cat("Error using Selenium to find game elements:", e$message, "\n")
  })
  
  # Method 3: Look for specific box score divs using the provided XPath pattern
  tryCatch({
    # Try variations of the XPath pattern
    xpath_variations <- c(
      "//div[contains(@class, 'box-score')]",
      "//div[contains(@class, 'game-box')]",
      "//div[contains(@class, 'score-box')]",
      "//div[@class='box']",
      "/html/body/div[3]//div[contains(@class, 'box')]"
    )
    
    for (xpath in xpath_variations) {
      elements <- page_html %>% html_nodes(xpath = xpath)
      if (length(elements) > 0) {
        cat(sprintf("Found %d elements using XPath: %s\n", length(elements), xpath))
        
        for (j in seq_along(elements)) {
          element_text <- elements[[j]] %>% html_text(trim = TRUE)
          if (nchar(element_text) > 0) {
            cat(sprintf("  Element %d: %s\n", j, substr(element_text, 1, 150)))
          }
        }
      }
    }
  }, error = function(e) {
    cat("Error with XPath variations:", e$message, "\n")
  })
  
  return(games)
}

# Function to extract specific box score data using the provided XPath pattern
extract_box_scores <- function(page_html, remDr = NULL) {
  # The example XPath: /html/body/div[3]/div/div/div[4]/div[4]/div[4]/div/div[2]/div[2]/div[1]/div
  # This suggests a nested structure
  
  box_scores <- list()
  
  cat("Extracting box scores using XPath pattern...\n")
  
  # Try the exact XPath pattern
  tryCatch({
    exact_xpath <- "/html/body/div[3]/div/div/div[4]/div[4]/div[4]/div/div[2]/div[2]/div[1]/div"
    elements <- page_html %>% html_nodes(xpath = exact_xpath)
    
    if (length(elements) > 0) {
      cat(sprintf("Found %d elements using exact XPath\n", length(elements)))
      for (i in seq_along(elements)) {
        box_text <- elements[[i]] %>% html_text(trim = TRUE)
        box_html <- elements[[i]] %>% as.character()
        
        box_scores[[length(box_scores) + 1]] <- list(
          text = box_text,
          html = box_html,
          xpath = exact_xpath
        )
      }
    } else {
      cat("Exact XPath did not match. Trying variations...\n")
      
      # Try variations - the structure might be slightly different
      # Try finding similar nested structures
      base_xpath <- "/html/body/div[3]//div"
      all_nested_divs <- page_html %>% html_nodes(xpath = base_xpath)
      
      cat(sprintf("Found %d nested divs in body > div[3]\n", length(all_nested_divs)))
      
      # Look for divs that might be box scores based on content
      for (i in seq_along(all_nested_divs)) {
        div_text <- all_nested_divs[[i]] %>% html_text(trim = TRUE)
        
        # Check if this looks like a box score (contains numbers, team names, etc.)
        if (grepl("\\d+.*\\d+|Team|Score|Points", div_text, ignore.case = TRUE) && 
            nchar(div_text) > 10 && nchar(div_text) < 1000) {
          
          box_scores[[length(box_scores) + 1]] <- list(
            text = div_text,
            html = all_nested_divs[[i]] %>% as.character(),
            index = i
          )
        }
      }
    }
  }, error = function(e) {
    cat("Error extracting box scores:", e$message, "\n")
  })
  
  # Also try using Selenium if available
  if (!is.null(remDr)) {
    tryCatch({
      # Try to find elements using Selenium's XPath
      selenium_elements <- remDr$findElements(using = "xpath", 
                                               value = "//div[contains(@class, 'box') or contains(@class, 'score')]")
      
      if (length(selenium_elements) > 0) {
        cat(sprintf("Found %d box score elements via Selenium\n", length(selenium_elements)))
        
        for (i in seq_along(selenium_elements)) {
          tryCatch({
            element_text <- selenium_elements[[i]]$getElementText()[[1]]
            if (nchar(element_text) > 0) {
              box_scores[[length(box_scores) + 1]] <- list(
                text = element_text,
                source = "selenium",
                index = i
              )
            }
          }, error = function(e) {
            # Skip
          })
        }
      }
    }, error = function(e) {
      cat("Error using Selenium for box scores:", e$message, "\n")
    })
  }
  
  return(box_scores)
}

# Helper function to cleanup ChromeDriver (if using wdman)
cleanup_chromedriver <- function() {
  if (exists("chrome_driver", envir = .GlobalEnv)) {
    tryCatch({
      chrome_driver <- get("chrome_driver", envir = .GlobalEnv)
      chrome_driver$stop()
      rm(chrome_driver, envir = .GlobalEnv)
      cat("ChromeDriver stopped and cleaned up\n")
    }, error = function(e) {
      cat("Error cleaning up ChromeDriver:", e$message, "\n")
    })
  } else {
    cat("No ChromeDriver instance found to clean up\n")
  }
}

# Helper function to stop Docker container (optional)
stop_docker_container <- function(container_name = "selenium-standalone-chrome", 
                                   remove = FALSE) {
  cat(sprintf("Stopping Docker container '%s'...\n", container_name))
  
  # Check if container exists and is running
  running_check <- system(sprintf("docker ps --format '{{.Names}}' | grep -q %s", container_name),
                         ignore.stdout = TRUE, ignore.stderr = TRUE)
  
  if (running_check == 0) {
    # Container is running, stop it
    stop_result <- system(sprintf("docker stop %s", container_name),
                         ignore.stdout = TRUE, ignore.stderr = TRUE)
    if (stop_result == 0) {
      cat("Container stopped successfully.\n")
      
      if (remove) {
        remove_result <- system(sprintf("docker rm %s", container_name),
                               ignore.stdout = TRUE, ignore.stderr = TRUE)
        if (remove_result == 0) {
          cat("Container removed successfully.\n")
        }
      }
    } else {
      cat("Failed to stop container.\n")
    }
  } else {
    cat("Container is not running.\n")
  }
}

# Run the scraper
# To run: source("00_data_scraper.R") or execute the function directly
# scrape_basketball_schedule()

# Example usage:
# Option 1: Using Docker (recommended - automatically starts container)
# results <- scrape_basketball_schedule(use_docker = TRUE)
# box_scores <- extract_box_scores(results$page_html)
# 
# Option 2: Using wdman (automatic ChromeDriver management)
# results <- scrape_basketball_schedule(use_docker = FALSE)
# box_scores <- extract_box_scores(results$page_html)
# cleanup_chromedriver()  # Cleanup when done
#
# Option 3: Stop Docker container when done (optional)
# stop_docker_container()  # Stops the container
# stop_docker_container(remove = TRUE)  # Stops and removes the container
#
# # Print summary
# cat("\n=== Scraping Summary ===\n")
# cat("Current URL:", results$current_url, "\n")
# cat("Games found:", nrow(results$games), "\n")
# cat("Potential game divs:", length(results$potential_game_divs), "\n")
# cat("Schedule elements:", results$schedule_elements, "\n")
# cat("Game rows:", results$game_rows, "\n")
# 
# # Save results
# saveRDS(results, "scraping_results.rds")
# write.csv(results$games, "schedule_games.csv", row.names = FALSE)
# cat("\nResults saved to scraping_results.rds and schedule_games.csv\n")