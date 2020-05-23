use Mix.Config

# config :logger,
#   console: [format: "[$level] $message\n"],
#   handle_sasl_reports: false,
#   handle_otp_reports: false

if function_exported?(Mix, :env, 0) and
     Mix.Project.get() == Mogs.MixProject and
     Mix.env() == :dev do
  config :todo, print: :silent, persist: true
else
  config :todo, print: :silent, persist: false
end
