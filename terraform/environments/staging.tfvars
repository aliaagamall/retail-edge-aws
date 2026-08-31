environment = "staging"

alb_deletion_protection = false

rds_instance_class          = "db.t3.micro"
rds_allocated_storage       = 20
rds_backup_retention_period = 7
rds_multi_az                = true
rds_skip_final_snapshot     = false
rds_deletion_protection     = true

redis_node_type                  = "cache.t3.micro"
redis_num_cache_clusters         = 2
redis_automatic_failover_enabled = true
redis_multi_az_enabled           = true
redis_auth_enabled               = true

secret_recovery_window_in_days = 30

app_instance_type = "t3.micro"

asg_min_size         = 2
asg_max_size         = 6
asg_desired_capacity = 2
