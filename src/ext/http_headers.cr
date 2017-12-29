require "http/headers"

def HTTP::Headers.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
  unless node.is_a?(YAML::Nodes::Mapping)
    node.raise "Expected mapping, not #{node.class}"
  end
  headers = new
  Hash(String, String).new(ctx, node).each do |key, value|
    headers[key] = value
  end
  headers
end
