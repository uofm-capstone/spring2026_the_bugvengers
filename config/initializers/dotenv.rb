# Load local environment variables for development/test when running outside docker-compose.
if defined?(Dotenv)
  env_file = ".env.#{Rails.env}"
  Dotenv.load(env_file, ".env")
end
