@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
@ObjectModel.sapObjectNodeType.name: 'ZYVEYVEND_CONTRA_1'
@EndUserText.label: '###GENERATED Core Data Service Entity'
define root view entity ZYVER_YVEND_CONTRA_1
  as select from YVEND_CONTRA_1
{
  key uuid as UUID,
  contract_id as ContractID,
  vendor_id as VendorID,
  vendor_name as VendorName,
  contract_title as ContractTitle,
  start_date as StartDate,
  end_date as EndDate,
  last_review_date as LastReviewDate,
  @Semantics.amount.currencyCode: 'Currency'
  contract_value as ContractValue,
  @Consumption.valueHelpDefinition: [ {
    entity.name: 'I_CurrencyStdVH', 
    entity.element: 'Currency', 
    useForValidation: true
  } ]
  currency as Currency,
  status as Status,
  buyer_id as BuyerID,
  approver_id as ApproverID,
  renewal_required as RenewalRequired,
  @Semantics.user.createdBy: true
  created_by as CreatedBy,
  @Semantics.systemDateTime.createdAt: true
  created_at as CreatedAt,
  @Semantics.user.lastChangedBy: true
  last_changed_by as LastChangedBy,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt
}
