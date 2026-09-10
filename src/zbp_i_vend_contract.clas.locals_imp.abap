CLASS lhc_YI_VEND_CONTRACT DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

       METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      keys REQUEST requested_authorizations FOR vendor_contract RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      REQUEST requested_authorizations FOR vendor_contract RESULT result.
    METHODS setinitialdefaultstatus FOR DETERMINE ON MODIFY
       keys FOR vendor_contract~setinitialdefaultstatus.
    METHODS validatedates FOR VALIDATE ON SAVE
       keys FOR vendor_contract~validatedates.
    METHODS validateamount FOR VALIDATE ON SAVE
       keys FOR vendor_contract~validateamount.
    METHODS calculaterenewalflag FOR DETERMINE ON MODIFY
       keys FOR vendor_contract~calculaterenewalflag.
    METHODS approve FOR MODIFY
       keys FOR ACTION vendor_contract~approve RESULT result.

    METHODS reject FOR MODIFY
       keys FOR ACTION vendor_contract~reject RESULT result.

    METHODS submit FOR MODIFY
       keys FOR ACTION vendor_contract~submit RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR vendor_contract RESULT result.

ENDCLASS.

CLASS lhc_YI_VEND_CONTRACT IMPLEMENTATION.

   METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD setInitialDefaultStatus.
    MODIFY ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky = key-%tky
                                    status = 'DRAFT' ) ).

  ENDMETHOD.

  METHOD validateDates.
    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( start_date end_date )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    IF lt_contracts IS NOT INITIAL.
      LOOP AT lt_contracts INTO DATA(ls_contract).
        IF ls_contract-end_date < ls_contract-start_date.
          APPEND VALUE #( %tky = ls_contract-%tky ) TO failed-vendor_contract.
          APPEND VALUE #( %tky = ls_contract-%tky
                          %msg = new_message( id       = 'ZMC_VENDOR_CONTRACT'
                                              number   = '001'
                                              severity = if_abap_behv_message=>severity-error )
                          %element-end_date = if_abap_behv=>mk-on
                           ) TO reported-vendor_contract.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD validateAmount.
    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( contract_value )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    IF lt_contracts IS NOT INITIAL.
      LOOP AT lt_contracts INTO DATA(ls_contract).
        IF ls_contract-contract_value LE 0.
          APPEND VALUE #( %tky = ls_contract-%tky ) TO failed-vendor_contract.
          APPEND VALUE #( %tky = ls_contract-%tky
                          %msg = new_message( id       = 'ZMC_VENDOR_CONTRACT'
                                              number   = '002'
                                              severity = if_abap_behv_message=>severity-error )
                          %element-contract_value =  if_abap_behv=>mk-on
                          ) TO reported-vendor_contract.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD calculateRenewalFlag.
    DATA lv_date TYPE d.
    lv_date = cl_abap_context_info=>get_system_date( ) + 30.

    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( end_date )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    MODIFY ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( renewal_required )
    WITH VALUE #( FOR ls_contract IN lt_contracts
                   ( %tky = ls_contract-%tky
                     renewal_required = COND #( WHEN ls_contract-end_date <= lv_date
                                                THEN abap_true
                                                ELSE abap_false ) ) ).
  ENDMETHOD.

  METHOD approve.
    MODIFY ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'APPROVED' ) ).
    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    ALL FIELDS WITH
    CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    result = VALUE #( FOR ls_contract IN lt_contracts ( %tky   = ls_contract-%tky
                                                        %param = ls_contract ) ).
  ENDMETHOD.

  METHOD reject.
    MODIFY ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'REJECTED' ) ).
    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    ALL FIELDS WITH
    CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    result = VALUE #( FOR ls_contract IN lt_contracts ( %tky   = ls_contract-%tky
                                                        %param = ls_contract ) ).
  ENDMETHOD.

  METHOD submit.
    MODIFY ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'SUBMITTED' ) ).

    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    ALL FIELDS WITH
    CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).
    result = VALUE #( FOR ls_contract IN lt_contracts ( %tky   = ls_contract-%tky
                                                        %param = ls_contract ) ).
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF yi_vend_contract IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( status )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

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
