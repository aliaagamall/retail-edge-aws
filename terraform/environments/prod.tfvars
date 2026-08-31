environment = "prod"

alb_deletion_protection = true

rds_instance_class          = "db.t3.micro"
rds_allocated_storage       = 30
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

app_instance_type = "t3.small"

asg_min_size         = 2
asg_max_size         = 10
asg_desired_capacity = 3

enable_black_friday_scaling = true

black_friday_scale_up_day   = 25
black_friday_scale_up_month = 11
black_friday_scale_up_hour  = 0

black_friday_scale_down_day   = 29
black_friday_scale_down_month = 11
black_friday_scale_down_hour  = 6

black_friday_min_size         = 10
black_friday_max_size         = 17
black_friday_desired_capacity = 15
