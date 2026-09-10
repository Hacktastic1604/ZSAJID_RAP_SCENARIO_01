@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Projection View'
@Metadata.allowExtensions: true
define root view entity YC_VEND_CONTRACT
  provider contract transactional_query
  as projection on YI_VEND_CONTRACT
{
  key     uuid,
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
          @ObjectModel.virtualElementCalculatedBy: 'ABAP:ZCL_VC_STATUS_CRIT'
  virtual status_criticality : abap.int1,
          buyer_id,
          approver_id,
          renewal_required,
          created_by,
          created_at,
          last_changed_by,
          last_changed_at,
          local_last_changed_at
}
   
