# Install necessary packages if they are not already installed
required_packages <- c("tidyverse", "fredr", "ggplot2", "lmtest", "sandwich", "broom", "dplyr", "zoo")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages)

# Load the packages
library(tidyverse)     # For data manipulation and visualization
library(fredr)         # For fetching data from FRED
library(ggplot2)       # For creating graphics
library(lmtest)        # For testing regression assumptions
library(sandwich)      # For robust standard errors
library(broom)         # To tidy up model outputs
library(dplyr)         # For data manipulation
library(zoo)           # For data aggregation

# Set FRED API key
fredr_set_key("fred_api_key")

# Function to fetch and clean FRED data
fetch_fred_data <- function(series_id, observation_start = as.Date("1970-01-01"), observation_end = Sys.Date()) {
  data <- fredr(series_id = series_id, observation_start = observation_start, observation_end = observation_end)
  data_clean <- na.omit(data[, c("date", "value")])
  data_clean <- data_clean %>% rename_with(~ c("date", series_id), everything())
  return(data_clean)
}

# Function to interpolate quarterly data to monthly
interpolate_to_monthly <- function(data, date_column, value_column, start_date, end_date) {
  date_seq <- seq(from = start_date, to = end_date, by = "month")
  approx_values <- na.approx(data[[value_column]], x = data[[date_column]], xout = date_seq, rule = 2)
  data.frame(date = date_seq, value = approx_values)
}

# Fetch the GDP data
gdp_data <- fetch_fred_data("GDP")


# Fetch real estate and economic indicators with date
housing_starts_data <- fetch_fred_data("HOUST")
housing_price_index_data <- fetch_fred_data("CSUSHPINSA")
mortgage_rate_data <- fetch_fred_data("MORTGAGE30US")
unemployment_rate_data <- fetch_fred_data("UNRATE")
gdp_data <- fetch_fred_data("GDP")

# Interpolate GDP data to monthly frequency
gdp_data_monthly <- interpolate_to_monthly(gdp_data, "date", "GDP", min(gdp_data$date), max(gdp_data$date))

# Merge all data frames by date and handle NAs
economic_data <- list(housing_starts_data, housing_price_index_data, mortgage_rate_data, unemployment_rate_data, gdp_data_monthly) %>%
  reduce(full_join, by = "date") %>%
  arrange(date) %>%
  na.omit()

# Verify the column names are correct
print(names(economic_data))

# Verify the head of the data
print(head(economic_data))

# Verify the end of the data
print(tail(economic_data))

# Merge all data frames by date and handle NAs
economic_data <- list(
  housing_starts_data, 
  housing_price_index_data, 
  mortgage_rate_data, 
  unemployment_rate_data, 
  gdp_data_monthly
) %>%
  reduce(full_join, by = "date") %>%
  arrange(date) %>%
  na.omit()

# Verify the column names are correct
print(names(economic_data))

# Verify the data
print(head(economic_data))

# Verify the end of the data
print(tail(economic_data))

# Building a regression model
model <- lm(CSUSHPINSA ~ HOUST + MORTGAGE30US + UNRATE + value, data = economic_data)

# Assumption Testing
# Check for linearity
plot(model)

# Check for homoscedasticity
plot(model, which = 3)

# Check for independence of residuals
plot(model, which = 5)

# Check for normality of residuals
shapiro.test(resid(model))

# Model Evaluation
summary(model)

# Test for multicollinearity
vif(model)

# Prediction
new_data <- data.frame(HOUST = c(1500, 1600, 1700),
                       MORTGAGE30US = c(3.5, 4.0, 4.5),
                       UNRATE = c(5.0, 5.5, 6.0),
                       value = c(25000, 26000, 27000))

# Predicting real estate prices
predicted_prices <- predict(model, newdata = new_data)

# Output the predicted prices
print(predicted_prices)

# Custom plotting function
plot_diagnostics <- function(model) {
  par(mfrow = c(2, 2))
  
  # Residuals vs Fitted with smoother line
  plot(fitted(model), residuals(model),
       xlab = "Fitted Values",
       ylab = "Residuals",
       main = "Residuals vs Fitted")
  abline(h = 0, col = "red")
  lines(lowess(fitted(model), residuals(model)), col = "blue")
  
  # Normal Q-Q plot
  qqnorm(resid(model),
         main = "Normal Q-Q",
         xlab = "Theoretical Quantiles",
         ylab = "Standardized Residuals")
  qqline(resid(model), col = "red")
  
  # Scale-Location plot
  plot(fitted(model), sqrt(abs(residuals(model))),
       xlab = "Fitted Values",
       ylab = "Sqrt(|Residuals|)",
       main = "Scale-Location")
  abline(h = 0, col = "red")
  lines(lowess(fitted(model), sqrt(abs(residuals(model)))), col = "blue")
  
  # Residuals vs Leverage
  plot(hatvalues(model), residuals(model),
       xlab = "Leverage",
       ylab = "Standardized Residuals",
       main = "Residuals vs Leverage")
  abline(h = 0, col = "red")
  abline(v = 0.5 * mean(hatvalues(model)), col = "blue", lty = 2) # Suggestive line for high leverage
}

# Call the custom plotting function
plot_diagnostics(model)

# Scatter plot with regression line for each predictor
economic_vars <- c("HOUST", "MORTGAGE30US", "UNRATE", "value")
plots <- list()

for (var in economic_vars) {
  p <- ggplot(economic_data, aes(x = .data[[var]], y = CSUSHPINSA)) +
    geom_point() +
    geom_smooth(method = "lm", col = "blue") +
    labs(x = var, y = "Real Estate Price Index", 
         title = paste("Impact of", var, "on Real Estate Prices")) +
    theme_minimal()
  plots[[var]] <- p
}

# Plotting the coefficient estimates
coef_df <- broom::tidy(model) %>%
  filter(term != "(Intercept)")

p_coef <- ggplot(coef_df, aes(x = term, y = estimate)) +
  geom_errorbar(aes(ymin = estimate - std.error, ymax = estimate + std.error), width = 0.2) +
  geom_point(size = 4) +
  labs(x = "Economic Indicators", y = "Effect on Real Estate Prices", 
       title = "Estimated Coefficients from Regression Model") +
  theme_minimal()

# Plotting predicted vs actual values
predictions <- data.frame(actual = economic_data$CSUSHPINSA, 
                          predicted = predict(model, newdata = economic_data))

p_pred_vs_act <- ggplot(predictions, aes(x = actual, y = predicted)) +
  geom_point() +
  geom_abline(intercept = 0, slope = 1, col = "red", linetype = "dashed") +
  labs(x = "Actual Real Estate Price Index", y = "Predicted Real Estate Price Index", 
       title = "Predicted vs Actual Real Estate Prices") +
  theme_minimal()

# Output each plot separately
for (var in economic_vars) {
  print(plots[[var]])
}

# Save each plot as a PNG file
for (var in economic_vars) {
  file_name <- paste0("plot_", var, ".png")
  ggsave(file_name, plot = plots[[var]], width = 10, height = 8)
}