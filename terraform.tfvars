# terraform.tfvars
env                 = "dev"
bucket_name         = "books-eda-covers-dev"
allowed_put_origins = ["http://localhost:3000"] # add your prod domain later
app_role_name       = "books-backend-role"      # your Spring app’s IAM role name
app_role_create  = true          # <— create it here
app_role_trust   = "ecs"         # or "lambda" / "ec2" depending on where Spring runs

