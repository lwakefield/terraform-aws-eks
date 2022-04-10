terraform-aws-eks
=================

This is _my_ flavor of eks. The main thing missing is auto-fixing the coredns install for fargate

```
terraform init
terraform apply

# get coredns working with fargate
# search for the compute-type: ec2 annotation and remove it
# alternatively follow https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html
kubectl edit deployment coredns -nkube-system
kubectl rollout restart -n kube-system deployment coredns
```
