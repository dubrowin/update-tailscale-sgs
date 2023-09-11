# update-tailscale-sgs
Update Tailscale Security Groups for an AWS instance

## Background
I run a pi-hole on an AWS EC2 instance and was seeing higher latency than I was suspecting, even after moving the EC2 instance into a region within my country.

I could see it was only available via a Relay. My first inclination was to start my own relay locally, but that was problematic.
Then [Owen V](https://www.linkedin.com/in/owenvalentine) shared a [Tailscale document](https://tailscale.com/kb/1082/firewall-ports/) with  me that indicated I only needed to open 1 specific UDP port. With the opening of the port, my latency dropped from 136ms to 6ms!

OK, so I had a configured security group allowing only my home IP, but what would happen when my IP changed or what if I was not in the house using my tablet or phone? I needed a better solution.

## The Clinch Pin
What I really needed was an easy and progamatic way to find the Public IP Address of my devices. After searching the web, playing with the tailscale command line, I finally found it. If the tailscale client is set to display JSON, it will show the Public IPs of all the devices. I devised this bash recipe to give me only the machine names and IPs.

    tailscale status --json --peers --active | grep -i "dnsname\|curaddr" | tail -n +3

This will show, in json, all peers that are active, find the dnsname and curaddr (current address) and then I use the tail command to remove the local host from the output.

## The Script
I already had a script that could do a simple update of a Security Group, so I added some additional functionality including multi-region (I have pi-holes that can operate in 2 regions).

### Configuration
There are essentially 3 things you need to setup:
- `REGIONS="il-central-1 us-west-2"` - I'm using the Israel and Oregon regions. You can modify/add a space separated list of the regions you want to use.
- I'm currently using different variables for the security group IDs that I need to update. Here are the IL and PDX security group variables
  - `ILSECGRP="sg-01111111111111111"`
  - `PDXSECGRP="sg-02222222222222222"`
- If you were to add additional regions, then you will need to update the FindRegion function's case statement to set the security group for the region.

### IAM Policy
I'm running this script on one of the pi-hole's themselves. It needs tailscale installed, but more than that, it requires permission to update the security groups involved.
I'm not an IAM expert, but I'm using this IAM policy to allow the EC2 instance to update the specific security groups

    {
      "Version": "2012-10-17",
      "Statement": [
      
          {
              "Sid": "VisualEditor0",
              "Effect": "Allow",
              "Action": "ec2:ModifySecurityGroupRules",
              "Resource": [
                  "arn:aws:ec2:il-central-1:<ACCOUNT ID>:security-group/sg-01111111111111111",
                  "arn:aws:ec2:us-west-2:<ACCOUNT ID>:security-group/sg-02222222222222222"
              ]
          },
          {
              "Sid": "VisualEditor1",
              "Effect": "Allow",
              "Action": [
                  "ec2:DescribeSecurityGroupRules",
                  "ec2:DescribeSecurityGroups"
              ],
              "Resource": "*"
          }
      ]
    }

### Installation
The script requires the AWS CLI.
I run the script via cron so that it executes every 5 minutes

    */5 * * * * /home/ubuntu/scripts/update-tailscale-sgs.sh
    
Options. There is a status option:

    usage: /home/ubuntu/scripts/update-tailscale-sgs.sh [ -s | --status ] [ -h | --help ]
            
## Next Steps
- I'd like to add the funcationality so that if an IP allowance rule hasn't been updated in x days (and is not currently being used), that it can be removed
- I'd also like to figure out a better way to configure the regions/security groups so that configuration doesn't require updating the case statement
    - and currently only 1 security group per region is supported
