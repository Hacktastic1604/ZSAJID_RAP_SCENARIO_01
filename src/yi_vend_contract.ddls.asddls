@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Root Interface View'
//@Metadata.ignorePropagatedAnnotations: true
define root view entity YI_VEND_CONTRACT
  as select from yvend_contract
{
  key uuid,
      contract_id,
      vendor_id,
      vendor_name,
      contract_title,
      start_date,
      end_date,
      last_review_date,
      contract_value,
      currency,
      status,
      buyer_id,
      approver_id,
      renewal_required,
      @Semantics.user.createdBy: true
      created_by,
      @Semantics.systemDateTime.createdAt: true
      created_at,
      @Semantics.user.lastChangedBy: true
      last_changed_by,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at
}
