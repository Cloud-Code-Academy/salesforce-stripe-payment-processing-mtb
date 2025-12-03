### Create scratch org based on definition file
`sf org scratch create --alias integration-stripe -v developer --definition-file config/stripe-scratch-def.json --duration-days 30 --set-default`

### Deploy metadata
`sf project deploy start`