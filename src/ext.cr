def Regex.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
  unless node.is_a?(YAML::Nodes::Scalar)
    node.raise "Expected scalar, not #{node.class}"
  end
  new(node.value)
end
