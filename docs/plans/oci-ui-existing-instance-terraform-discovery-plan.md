# Plan: OCI UI Terraform Discovery For Existing Production Instance

Date: 2026-06-13
Status: Safety-first operator plan

Related documents:

- `docs/ci-cd.md`
- `deploy/README.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- Oracle OCI Terraform Provider:
  `https://docs.oracle.com/iaas/Content/dev/terraform/home.htm`
- Oracle Resource Manager Resource Discovery:
  `https://docs.oracle.com/iaas/Content/ResourceManager/Concepts/resource-discovery.htm`
- Oracle Resource Manager stack from existing compartment:
  `https://docs.oracle.com/iaas/Content/ResourceManager/Tasks/create-stack-compartment.htm`
- Oracle Resource Manager plan job:
  `https://docs.oracle.com/iaas/Content/ResourceManager/Tasks/create-job-plan.htm`

## Scope

This plan describes how to use the OCI Console UI to discover the existing OCI
production infrastructure into a Terraform/Resource Manager stack without
replacing the scarce Always Free A1 compute instance.

The first pass is read/discovery/plan only. It must not apply, destroy, or
replace infrastructure.

## Goal

Generate Terraform configuration and state from existing OCI resources so the
current production instance can be documented and reviewed as infrastructure as
code without risking reprovisioning.

## Non-Goals

- Recreate the current OCI instance.
- Run a Terraform apply against production.
- Run a Terraform destroy job.
- Move the production instance to another compartment, region, or availability
  domain.
- Prove that generated Terraform is clean enough for long-term automation on
  the first pass.

## Safety Rules

- Do not click **Apply**.
- Do not click **Destroy**.
- Do not delete the stack if it is the only copy of generated configuration or
  state that you still need.
- Treat Terraform state as sensitive. Oracle documents that state files contain
  resource attributes and should be protected when sensitive data is involved.
- If any plan output says the compute instance will be replaced, deleted,
  terminated, or recreated, stop.
- If the UI prompts for an action you do not recognize, stop and record the
  exact screen text before continuing.

## Step 1: Identify The Existing Resource Boundary

In the OCI Console:

1. Go to **Compute** -> **Instances**.
2. Open the current production A1 instance.
3. Record the following non-secret values in your deployment notes:
   - instance display name
   - instance OCID
   - compartment
   - region
   - availability domain
   - shape
   - VCN
   - subnet
   - public IP assignment shape, if shown
4. Do not terminate, stop, move, resize, or edit the instance from this page.

Decision point:

- If all production resources are in one non-root compartment, use that
  compartment for discovery.
- If production resources span multiple compartments, discover one compartment
  at a time. Oracle Resource Manager resource discovery creates a stack from a
  single compartment.
- If the instance is in the tenancy root compartment, proceed carefully and
  restrict discovery to selected services rather than discovering every
  supported tenancy-level resource.

## Step 2: Create A Resource Manager Stack From Existing Compartment

In the OCI Console:

1. Open the navigation menu.
2. Go to **Developer Services** -> **Resource Manager** -> **Stacks**.
3. Click **Create stack**.
4. Under **Choose the origin of the Terraform configuration**, select
   **Existing compartment**.
5. Select the compartment that contains the production instance.
6. Select the region where the production instance runs.
7. For service selection, prefer **Selected** rather than all services on the
   first pass.
8. Select only the services needed to capture the core baseline first:
   - `core` for compute, VCN, subnet, route/security resources, public IP
     resources, and related networking
9. Name the stack clearly, for example:
   `budget-analyzer-prod-discovery-readonly`
10. Put the stack in the same administrative compartment you use for production
    operations, unless you have a separate IaC/admin compartment.
11. Do not put secrets in the stack name, description, or tags.
12. Review the summary.
13. Click **Create**.

Expected result:

- OCI starts a work request and then a Resource Manager job that generates
  Terraform configuration for the selected compartment resources.
- This should capture existing resources into generated configuration and
  state. It should not create a replacement compute instance.

## Step 3: Wait For Discovery To Finish

In the stack details page:

1. Open the **Jobs** section.
2. Wait for the discovery/generation job to finish.
3. Confirm the job reaches a successful state.
4. Open the job logs if it fails.
5. Save the failure text in notes before retrying or changing scope.

Do not run **Apply** after discovery succeeds.

## Step 4: Inspect Generated Configuration

In the stack details page:

1. Find the generated Terraform configuration.
2. Use the UI option to view it in Code Editor or download the configuration.
3. Confirm the generated configuration includes the existing instance as an
   `oci_core_instance` resource.
4. Confirm it includes the expected VCN/subnet/security resources.
5. Look for placeholder comments or missing attributes. Oracle documents that
   resource discovery can omit some attributes when OCI services do not return
   them or when sensitive values are not discoverable.

Do not edit generated configuration yet unless you are only making a local copy
for review.

## Step 5: Inspect Terraform State

In the stack or completed job details:

1. Use the UI option to view state for the completed job.
2. Confirm the state references the existing instance OCID from Step 1.
3. Confirm it does not reference a newly created replacement instance.
4. Do not publish the state file in the repo.
5. Do not paste state contents into issues, chat, docs, or AI prompts.

## Step 6: Run A Plan Job Only

In the stack details page:

1. Click **Plan**.
2. If the UI offers advanced options, enable refresh of resource state before
   checking differences.
3. Keep default parallelism unless there is a specific reason to change it.
4. Create the plan job.
5. Wait for the plan job to finish.
6. Open the plan output/logs.

Acceptable first-pass outcomes:

- no changes
- read-only refresh differences
- generated-configuration noise that needs manual cleanup before any future
  apply

Stop immediately if the plan proposes:

- destroying the compute instance
- replacing the compute instance
- changing the instance shape
- changing the boot volume in a destructive way
- deleting the public IP, subnet, VCN, route table, security list, or NSG used
  by production
- removing resources that you do not understand

## Step 7: Record Evidence

Record a short run note outside secrets/state files:

- date
- operator
- OCI region
- discovered compartment
- selected discovery services
- stack name
- discovery job result
- plan job result
- whether the existing compute instance OCID matched the generated state
- whether the plan was no-op or contained changes
- any missing attributes or placeholder values found

Do not record Terraform state contents.

## Step 8: Decide Whether To Continue

If the plan is clean or understandable:

1. Download the generated Terraform configuration for local review.
2. Do not commit it directly as production IaC yet.
3. Create a follow-up plan to convert generated Resource Manager output into a
   curated `infra/oci/` Terraform/OpenTofu module.
4. Add lifecycle protection such as `prevent_destroy` for the existing compute
   instance before any future apply path is considered.

If the plan is noisy or proposes replacement:

1. Do not apply.
2. Keep the current production instance manually managed.
3. Save the plan output as private operator evidence if needed.
4. Narrow discovery scope or manually import only low-risk resources in a later
   plan.

## Completion Criteria

- A Resource Manager stack exists from existing-compartment discovery.
- The generated state references the current production instance OCID.
- A plan job has been run without applying changes.
- No destroy/apply job has been run.
- The operator understands whether Terraform can represent the current OCI
  baseline without replacing the A1 instance.

