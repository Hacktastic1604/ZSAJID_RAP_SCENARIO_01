CLASS lhc_vendor_contract1 DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    "--------------------------------------------------------------------
    " RAP behavior handler architecture
    "--------------------------------------------------------------------
    " This local handler class is the RAP implementation layer for the
    " `vendor_contract` business object. RAP splits behavior into a few
    " clear responsibilities:
    "   - authorization methods decide what the current user may access
    "   - validation methods protect data quality before save
    "   - determination methods calculate derived values automatically
    "   - action methods implement workflow steps like submit/approve/reject
    "   - feature methods enable/disable actions dynamically in the UI
    "
    " This separation keeps business rules close to the entity, makes the
    " UI metadata-driven, and lets the framework orchestrate save, action,
    " and response handling consistently in local transaction mode.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
   keys REQUEST requested_authorizations FOR vendor_contract1 RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      REQUEST requested_authorizations FOR vendor_contract1 RESULT result.

    METHODS setinitialdefaultstatus FOR DETERMINE ON MODIFY
       keys FOR vendor_contract1~setinitialdefaultstatus.

    METHODS validatedates FOR VALIDATE ON SAVE
       keys FOR vendor_contract1~validatedates.

    METHODS validateamount FOR VALIDATE ON SAVE
       keys FOR vendor_contract1~validateamount.

    METHODS calculaterenewalflag FOR DETERMINE ON MODIFY
       keys FOR vendor_contract1~calculaterenewalflag.

    METHODS approve FOR MODIFY
       keys FOR ACTION vendor_contract1~approve RESULT result.


    METHODS reject FOR MODIFY
       keys FOR ACTION vendor_contract1~reject RESULT result.

    METHODS submit FOR MODIFY
       keys FOR ACTION vendor_contract1~submit RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR vendor_contract1 RESULT result.

ENDCLASS.

CLASS lhc_vendor_contract1 IMPLEMENTATION.

  "--------------------------------------------------------------------
  " Authorization hooks
  "--------------------------------------------------------------------
  " These methods are part of the RAP handler contract. They are kept
  " in place even when no custom authorization logic is needed, because
  " the framework still calls them during feature and authorization checks.
  " By explicitly implementing them, the behavior definition remains ready
  " for future rule-based access control without changing the class shape.

  METHOD get_instance_authorizations.
    " Currently no row-level authorization restriction is applied.
    " The framework will still call this method when it evaluates whether
    " the current user may see or change specific contract instances.
  ENDMETHOD.

  METHOD get_global_authorizations.
    " No global (entity-wide) authorization logic is required yet.
    " This placeholder keeps the RAP handler complete and allows the
    " business team to add global access rules later without redesigning
    " the class interface.
  ENDMETHOD.

  METHOD setInitialDefaultStatus.
    " On create/modify, initialize new contracts with DRAFT status so
    " they begin in a safe, non-final state and can later move through
    " submit/approve/reject workflow steps in a controlled manner.
    " MODIFY ENTITIES updates the draft record in local mode, which means
    " the change is applied inside the current RAP transaction before save.
    MODIFY ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky = key-%tky
                                    status = 'DRAFT' ) ).

  ENDMETHOD.

  METHOD validateDates.
    " Validate business consistency before save: the end date must not be
    " earlier than the start date. This prevents impossible contracts from
    " being persisted and gives the user field-specific feedback.
    " READ ENTITIES fetches only the date fields needed for validation so
    " the method stays efficient and only checks the records selected by the
    " current RAP request.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    FIELDS ( start_date end_date )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    IF lt_contracts IS NOT INITIAL.
      " LOOP AT iterates over the fetched records and evaluates each record
      " independently so the framework can report precise field-level errors.
      LOOP AT lt_contracts INTO DATA(ls_contract).
        IF ls_contract-end_date < ls_contract-start_date.
          " failed-vendor_contract marks the instance as invalid for save,
          " while reported-vendor_contract carries the user-facing message and
          " points the error to the end_date field for easy correction.
          APPEND VALUE #( %tky = ls_contract-%tky ) TO failed-vendor_contract1.
          APPEND VALUE #( %tky = ls_contract-%tky
                          %msg = new_message( id       = 'ZMC_VENDOR_CONTRACT'
                                              number   = '001'
                                              severity = if_abap_behv_message=>severity-error )
                          %element-end_date = if_abap_behv=>mk-on
                           ) TO reported-vendor_contract1.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD validateAmount.
    " Validate that the contract value is positive. This protects downstream
    " approval and reporting logic from zero or negative amounts, which would
    " not make sense for a vendor contract amount.
    " The READ ENTITIES statement keeps the validation focused only on the
    " amount field that is required for this business rule.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    FIELDS ( contract_value )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    IF lt_contracts IS NOT INITIAL.
      " Each row is checked individually so only the invalid contracts are
      " rejected and the corresponding field gets highlighted in the UI.
      LOOP AT lt_contracts INTO DATA(ls_contract).
        IF ls_contract-contract_value LE 0.
          " The failed/reported pattern is the RAP way of stopping the save
          " and returning a precise message for the affected field.
          APPEND VALUE #( %tky = ls_contract-%tky ) TO failed-vendor_contract1.
          APPEND VALUE #( %tky = ls_contract-%tky
                          %msg = new_message( id       = 'ZMC_VENDOR_CONTRACT'
                                              number   = '002'
                                              severity = if_abap_behv_message=>severity-error )
                          %element-contract_value =  if_abap_behv=>mk-on
                          ) TO reported-vendor_contract1.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD calculateRenewalFlag.
    " Determine whether renewal is required by comparing the end date with
    " a rolling 30-day horizon from the current system date. This keeps the
    " flag derived automatically whenever the record changes, so users do not
    " have to maintain it manually.
    " cl_abap_context_info=>get_system_date( ) returns the current application
    " server date, and adding 30 creates the threshold used for the renewal rule.
    DATA lv_date TYPE d.
    lv_date = cl_abap_context_info=>get_system_date( ) + 30.

    " Read the current end dates first; the flag is based on existing entity
    " data and should be derived from the persisted state, not hard-coded.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    FIELDS ( end_date )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    " Update the derived renewal flag in the same transaction so the user sees
    " the calculated value immediately after the record changes.
    MODIFY ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    UPDATE FIELDS ( renewal_required )
    WITH VALUE #( FOR ls_contract IN lt_contracts
                   ( %tky = ls_contract-%tky
                     renewal_required = COND #( WHEN ls_contract-end_date <= lv_date
                                                THEN abap_true
                                                ELSE abap_false ) ) ).
  ENDMETHOD.

  METHOD approve.
    " Approve transitions the contract to APPROVED and returns the updated
    " entity data. Returning the final state back to the framework allows the
    " UI to refresh immediately after the action executes.
    " The entity update writes only the status field, keeping the action
    " focused and avoiding unintended changes to other business data.
    MODIFY ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'APPROVED' ) ).
    " READ ENTITIES retrieves the full post-action image so the framework can
    " return the updated contract data to the caller.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    ALL FIELDS WITH
    CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    " Build the action result table expected by RAP: %param carries the
    " updated business object back to the UI or calling process.
    result = VALUE #( FOR ls_contract IN lt_contracts ( %tky   = ls_contract-%tky
                                                        %param = ls_contract ) ).
  ENDMETHOD.

  METHOD reject.
    " Reject transitions the contract to REJECTED and returns the updated
    " data so the object page/list report can reflect the state change right
    " away without requiring a manual reload.
    " The update is intentionally limited to the workflow status field.
    MODIFY ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'REJECTED' ) ).
    " Fetch the updated state after the rejection so the action response is
    " consistent with the latest persisted values in the local transaction.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    ALL FIELDS WITH
    CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    " Return the rejected contract rows to the framework as the action result.
    result = VALUE #( FOR ls_contract IN lt_contracts ( %tky   = ls_contract-%tky
                                                        %param = ls_contract ) ).
  ENDMETHOD.

  METHOD submit.
    " Submit moves the contract from draft into the review workflow. Like the
    " other action methods, it updates the business state and returns the fresh
    " entity image so the UI always stays in sync with the backend state.
    " Again, only the status field changes here because the purpose of the
    " action is workflow progression, not master-data maintenance.
    MODIFY ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'SUBMITTED' ) ).

    " Read the full entity data after submit so the caller receives the latest
    " object state immediately.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    ALL FIELDS WITH
    CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    " Convert the fetched rows into the result structure required by RAP.
    result = VALUE #( FOR ls_contract IN lt_contracts ( %tky   = ls_contract-%tky
                                                        %param = ls_contract ) ).
  ENDMETHOD.

  METHOD get_instance_features.
    " Enable or disable actions dynamically based on the current contract
    " status. This is how RAP keeps the UI safe: users only see actions that
    " make sense for the current state (for example, only submitted contracts
    " can be approved or rejected).
    " Read only the status field because feature control depends solely on the
    " workflow state, not the other contract attributes.
    READ ENTITIES OF yi_vend_contra_1 IN LOCAL MODE
    ENTITY vendor_contract1
    FIELDS ( status )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    " Build feature flags per instance. The UI uses these flags to enable or
    " disable the action buttons without extra round-trips or custom logic.
    result = VALUE #( FOR ls_contract IN lt_contracts
                    ( %tky = ls_contract-%tky
                      %action-submit = COND #( WHEN ls_contract-status = 'DRAFT'
                                               THEN if_abap_behv=>fc-o-enabled
                                               ELSE if_abap_behv=>fc-o-disabled  )
                      %action-approve = COND #( WHEN ls_contract-status = 'SUBMITTED'
                                               THEN if_abap_behv=>fc-o-enabled
                                               ELSE if_abap_behv=>fc-o-disabled )
                      %action-reject  = COND #( WHEN ls_contract-status = 'SUBMITTED'
                                               THEN if_abap_behv=>fc-o-enabled
                                               ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

ENDCLASS.
