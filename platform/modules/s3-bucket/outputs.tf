# Task 11d — S3 Bucket module outputs

output "bucket_id" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.bucket.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.bucket.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket"
  value       = aws_s3_bucket.bucket.bucket_regional_domain_name
}

output "bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.bucket.region
}
