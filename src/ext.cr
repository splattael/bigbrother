def Regex.new(pull : YAML::PullParser)
  new(pull.read_scalar)
end
