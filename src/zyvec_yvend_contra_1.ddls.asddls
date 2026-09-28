@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@Endusertext: {
  Label: '###GENERATED Core Data Service Entity'
}
@Objectmodel: {
  Sapobjectnodetype.Name: 'ZYVEYVEND_CONTRA_1'
}
@AccessControl.authorizationCheck: #MANDATORY
define root view entity ZYVEC_YVEND_CONTRA_1
  provider contract TRANSACTIONAL_QUERY
  as projection on ZYVER_YVEND_CONTRA_1
  association [1..1] to ZYVER_YVEND_CONTRA_1 as _BaseEntity on $projection.UUID = _BaseEntity.UUID
{
  key UUID,
  ContractID,
  VendorID,
  VendorName,
  ContractTitle,
  StartDate,
  EndDate,
  LastReviewDate,
  @Semantics: {
    Amount.Currencycode: 'Currency'
  }
  ContractValue,
  @Consumption: {
    Valuehelpdefinition: [ {
      Entity.Element: 'Currency', 
      Entity.Name: 'I_CurrencyStdVH', 
      Useforvalidation: true
    } ]
  }
  Currency,
  Status,
  BuyerID,
  ApproverID,
  RenewalRequired,
  @Semantics: {
    User.Createdby: true
  }
  CreatedBy,
  @Semantics: {
    Systemdatetime.Createdat: true
  }
  CreatedAt,
  @Semantics: {
    User.Lastchangedby: true
  }
  LastChangedBy,
  @Semantics: {
    Systemdatetime.Lastchangedat: true
  }
  LastChangedAt,
  @Semantics: {
    Systemdatetime.Localinstancelastchangedat: true
  }
  LocalLastChangedAt,
  _BaseEntity
}
