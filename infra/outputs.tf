output "agent_id" {
  value = yandex_loadtesting_agent.load_generator.id
}

output "db_cluster_id" {
  value = module.db.cluster_id
}

