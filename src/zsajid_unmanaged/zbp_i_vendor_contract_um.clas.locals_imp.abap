" Helper buffer class used to store staged (create/update/delete) changes
" for the unmanaged RAP implementation. This keeps DB operations batched
" and deferred until the saver commits.
CLASS lcl_contract_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-DATA gt_create TYPE STANDARD TABLE OF YVEND_CONTRACT WITH DEFAULT KEY.
    CLASS-DATA gt_update TYPE STANDARD TABLE OF YVEND_CONTRACT WITH DEFAULT KEY.
    CLASS-DATA gt_delete TYPE STANDARD TABLE OF sysuuid_x16 WITH DEFAULT KEY.

    CLASS-METHODS reset.
ENDCLASS.

CLASS lcl_contract_buffer IMPLEMENTATION.
  " Reset the in-memory change buffers. Called after save/cleanup to ensure
  " no stale staged changes remain between requests.
  METHOD reset.
    CLEAR: gt_create, gt_update, gt_delete.
  ENDMETHOD.
ENDCLASS.

" Behavior handler for the vendor_contract entity in the unmanaged RAP
" scenario. Contains CRUD handlers and business logic (validation,
" actions) that operate on the change buffer rather than direct DB
" persistence during runtime operations.
CLASS lhc_vendor_contract DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR vendor_contract RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      keys REQUEST requested_authorizations FOR vendor_contract RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      REQUEST requested_authorizations FOR vendor_contract RESULT result.

    METHODS create FOR MODIFY
       entities FOR CREATE vendor_contract.

    METHODS update FOR MODIFY
       entities FOR UPDATE vendor_contract.

    METHODS delete FOR MODIFY
       keys FOR DELETE vendor_contract.

    METHODS read FOR READ
       keys FOR READ vendor_contract RESULT result.

    METHODS lock FOR LOCK
       keys FOR LOCK vendor_contract.

    METHODS approve FOR MODIFY
       keys FOR ACTION vendor_contract~approve RESULT result.

    METHODS reject FOR MODIFY
       keys FOR ACTION vendor_contract~reject RESULT result.

    METHODS submit FOR MODIFY
       keys FOR ACTION vendor_contract~submit RESULT result.

    METHODS calculateRenewalFlag FOR DETERMINE ON MODIFY
       keys FOR vendor_contract~calculateRenewalFlag.

    METHODS setInitialDefaultStatus FOR DETERMINE ON MODIFY
       keys FOR vendor_contract~setInitialDefaultStatus.

    METHODS validateAmount FOR VALIDATE ON SAVE
       keys FOR vendor_contract~validateAmount.

    METHODS validateDates FOR VALIDATE ON SAVE
       keys FOR vendor_contract~validateDates.

ENDCLASS.

CLASS lhc_vendor_contract IMPLEMENTATION.

  " Determine available actions (features) for each instance based on
  " its current status. Called by the RAP runtime to enable/disable UI
  " actions like submit/approve/reject.
  "
  " Parameters (implementation context):
  " - keys: table of incoming key rows identifying instances to evaluate
  " - requested_features: structure describing which features the runtime
  "   inquires for (not modified here)
  " - result: table of feature flags for each instance. Each row includes
  "   %tky (technical key) and feature flags like %action-submit
  "
  " Example flow:
  " - UI asks for actions for contract with status 'DRAFT'
  " - This method returns %action-submit enabled, approve/reject disabled
  METHOD get_instance_features.
    READ ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( status )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    result = VALUE #( FOR ls_contract IN lt_contracts
                    ( %tky = ls_contract-%tky
                      %action-submit = COND #( WHEN ls_contract-status = 'DRAFT'
                                               THEN if_abap_behv=>fc-o-enabled
                                               ELSE if_abap_behv=>fc-o-disabled )
                      %action-approve = COND #( WHEN ls_contract-status = 'SUBMITTED'
                                                THEN if_abap_behv=>fc-o-enabled
                                                ELSE if_abap_behv=>fc-o-disabled )
                      %action-reject = COND #( WHEN ls_contract-status = 'SUBMITTED'
                                               THEN if_abap_behv=>fc-o-enabled
                                               ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.

  " Placeholder for instance-level authorization logic. Can be extended
  " to restrict operations per user/role.
  "
  " Parameters:
  " - keys: incoming key rows for which to compute authorizations
  " - requested_authorizations: requested authorization categories
  " - result: authorization decisions to be returned to the RAP runtime
  METHOD get_instance_authorizations.
  ENDMETHOD.

  " Placeholder for global authorizations across the entity set.
  "
  " Parameters:
  " - requested_authorizations: requested global authorization categories
  " - result: structure to return global authorization decisions
  METHOD get_global_authorizations.
  ENDMETHOD.

  " Handle CREATE operations by populating defaults, generating UUIDs and
  " staging the new records in the create buffer. No DB insert happens
  " here; actual persistence occurs in the saver `save` method.
  "
  " Parameters:
  " - entities: table of incoming entity payloads to create. Each row may
  "   include a client id (%cid) and field values for the new contract.
  "
  " Side effects / outputs:
  " - Appends staged rows to lcl_contract_buffer=>gt_create
  " - Populates mapped-vendor_contract with mapping rows containing %cid
  "   and the generated uuid so the caller can correlate client requests
  "   with the created server-side instances.
  "
  " Example flow:
  " - Client POSTs two new contracts without uuids
  " - This method assigns uuids, sets defaults and stages them
  " - mapped-vendor_contract returns two rows with %cid -> uuid mappings
  METHOD create.
    DATA lv_date TYPE d.
    DATA lv_timestamp TYPE timestampl.
    DATA lt_create TYPE STANDARD TABLE OF YVEND_CONTRACT.

    lv_date = cl_abap_context_info=>get_system_date( ) + 30.
    GET TIME STAMP FIELD lv_timestamp.

    lt_create = CORRESPONDING #( entities ).

    LOOP AT lt_create ASSIGNING FIELD-SYMBOL(<ls_create>).
      IF <ls_create>-uuid IS INITIAL.
        TRY.
          <ls_create>-uuid = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error INTO DATA(lx_uuid).
          " UUID generation failed for this incoming row. Report and skip it
          " so the RAP runtime receives a clear reported/failure entry instead
          " of an uncaught exception.
          APPEND VALUE #( %cid = entities[ sy-tabix ]-%cid ) TO failed-vendor_contract.
          APPEND VALUE #( %cid = entities[ sy-tabix ]-%cid
                          %msg = new_message_with_text(
                                   severity = if_abap_behv_message=>severity-error
                                   text = lx_uuid->get_text( ) ) )
            TO reported-vendor_contract.
          CONTINUE.
        ENDTRY.
      ENDIF.

      IF <ls_create>-status IS INITIAL.
        <ls_create>-status = 'DRAFT'.
      ENDIF.

      <ls_create>-renewal_required = COND #( WHEN <ls_create>-end_date IS NOT INITIAL
                                               AND <ls_create>-end_date <= lv_date
                                             THEN abap_true
                                             ELSE abap_false ).
      <ls_create>-created_by = sy-uname.
      <ls_create>-created_at = lv_timestamp.
      <ls_create>-last_changed_by = sy-uname.
      <ls_create>-last_changed_at = lv_timestamp.
      <ls_create>-local_last_changed_at = lv_timestamp.

      DELETE lcl_contract_buffer=>gt_delete WHERE table_line = <ls_create>-uuid.
      DELETE lcl_contract_buffer=>gt_create WHERE uuid = <ls_create>-uuid.
      DELETE lcl_contract_buffer=>gt_update WHERE uuid = <ls_create>-uuid.
      APPEND <ls_create> TO lcl_contract_buffer=>gt_create.
    ENDLOOP.

    LOOP AT lt_create INTO DATA(ls_create).
      APPEND VALUE #( %cid = entities[ sy-tabix ]-%cid
                      uuid = ls_create-uuid )
        TO mapped-vendor_contract.
    ENDLOOP.
  ENDMETHOD.

  " Handle UPDATE operations by resolving the current state (either from
  " create-buffer or DB), applying field updates, updating timestamps and
  " staging into the update buffer. Guarded to skip updates without UUID.
  "
  " Parameters:
  " - entities: table of incoming entity updates. Each row contains control
  "   flags (%control-<field>) indicating which fields were modified by the
  "   client. Only fields marked as controlled are applied to the staged row.
  "
  " Behavior notes:
  " - If an entity is already staged in gt_create, the staged entry is
  "   updated in place (so a create followed by update remains a create).
  " - Otherwise the DB row is selected and a staged update row is created
  "   and added to gt_update. Any existing delete staging is removed.
  METHOD update.
    DATA lv_date TYPE d.
    DATA lv_timestamp TYPE timestampl.

    lv_date = cl_abap_context_info=>get_system_date( ) + 30.
    GET TIME STAMP FIELD lv_timestamp.

    LOOP AT entities INTO DATA(ls_entity).
      " Guard: if the incoming entity has no UUID we cannot resolve a DB row -> skip
      IF ls_entity-uuid IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE lcl_contract_buffer=>gt_create
        WITH KEY uuid = ls_entity-uuid
        INTO DATA(ls_db_contract).

      IF sy-subrc <> 0.
        SELECT SINGLE *
          FROM YVEND_CONTRACT
          WHERE uuid = @ls_entity-uuid
          INTO @ls_db_contract.

        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.

      IF ls_entity-%control-contract_id = if_abap_behv=>mk-on.
        ls_db_contract-contract_id = ls_entity-contract_id.
      ENDIF.
      IF ls_entity-%control-vendor_id = if_abap_behv=>mk-on.
        ls_db_contract-vendor_id = ls_entity-vendor_id.
      ENDIF.
      IF ls_entity-%control-vendor_name = if_abap_behv=>mk-on.
        ls_db_contract-vendor_name = ls_entity-vendor_name.
      ENDIF.
      IF ls_entity-%control-contract_title = if_abap_behv=>mk-on.
        ls_db_contract-contract_title = ls_entity-contract_title.
      ENDIF.
      IF ls_entity-%control-start_date = if_abap_behv=>mk-on.
        ls_db_contract-start_date = ls_entity-start_date.
      ENDIF.
      IF ls_entity-%control-end_date = if_abap_behv=>mk-on.
        ls_db_contract-end_date = ls_entity-end_date.
        ls_db_contract-renewal_required = COND #( WHEN ls_db_contract-end_date IS NOT INITIAL
                                                    AND ls_db_contract-end_date <= lv_date
                                                  THEN abap_true
                                                  ELSE abap_false ).
      ENDIF.
      IF ls_entity-%control-last_review_date = if_abap_behv=>mk-on.
        ls_db_contract-last_review_date = ls_entity-last_review_date.
      ENDIF.
      IF ls_entity-%control-contract_value = if_abap_behv=>mk-on.
        ls_db_contract-contract_value = ls_entity-contract_value.
      ENDIF.
      IF ls_entity-%control-currency = if_abap_behv=>mk-on.
        ls_db_contract-currency = ls_entity-currency.
      ENDIF.
      IF ls_entity-%control-status = if_abap_behv=>mk-on.
        ls_db_contract-status = ls_entity-status.
      ENDIF.
      IF ls_entity-%control-buyer_id = if_abap_behv=>mk-on.
        ls_db_contract-buyer_id = ls_entity-buyer_id.
      ENDIF.
      IF ls_entity-%control-approver_id = if_abap_behv=>mk-on.
        ls_db_contract-approver_id = ls_entity-approver_id.
      ENDIF.
      IF ls_entity-%control-renewal_required = if_abap_behv=>mk-on.
        ls_db_contract-renewal_required = ls_entity-renewal_required.
      ENDIF.

      ls_db_contract-last_changed_by = sy-uname.
      ls_db_contract-last_changed_at = lv_timestamp.
      ls_db_contract-local_last_changed_at = lv_timestamp.

      READ TABLE lcl_contract_buffer=>gt_create
        WITH KEY uuid = ls_entity-uuid
        TRANSPORTING NO FIELDS.

      IF sy-subrc = 0.
        DELETE lcl_contract_buffer=>gt_create WHERE uuid = ls_entity-uuid.
        APPEND ls_db_contract TO lcl_contract_buffer=>gt_create.
      ELSE.
        DELETE lcl_contract_buffer=>gt_update WHERE uuid = ls_entity-uuid.
        DELETE lcl_contract_buffer=>gt_delete WHERE table_line = ls_entity-uuid.
        APPEND ls_db_contract TO lcl_contract_buffer=>gt_update.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " Handle DELETE operations by removing any staged create/update entries
  " for the UUID and, if the record exists in DB, staging the UUID into
  " the delete buffer for later deletion on save.
  "
  " Parameters:
  " - keys: table of key rows indicating which instances to delete.
  "
  " Side effects:
  " - Removes any create/update staging for the given UUID
  " - If the UUID exists in the active table, appends the UUID to
  "   lcl_contract_buffer=>gt_delete so `save` will delete it from DB.
  METHOD delete.
    LOOP AT keys INTO DATA(ls_key).
      DELETE lcl_contract_buffer=>gt_create WHERE uuid = ls_key-uuid.
      DELETE lcl_contract_buffer=>gt_update WHERE uuid = ls_key-uuid.

        SELECT SINGLE uuid
          FROM YVEND_CONTRACT
        WHERE uuid = @ls_key-uuid
        INTO @DATA(lv_uuid).

      IF sy-subrc = 0.
        DELETE lcl_contract_buffer=>gt_delete WHERE table_line = ls_key-uuid.
        APPEND ls_key-uuid TO lcl_contract_buffer=>gt_delete.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " Handle READ operations. Filters out empty keys to avoid unintended
  " FOR ALL ENTRIES behaviour and returns matching rows from the active
  " table.
  "
  " Parameters:
  " - keys: table of requested key rows. Rows with initial/empty uuid are
  "   ignored to prevent accidental full-table selects.
  " - result: table of corresponding entity rows returned to the caller.
  METHOD read.
    IF keys IS INITIAL.
      RETURN.
    ENDIF.

    " Filter out any keys that have an initial/empty uuid. FOR ALL ENTRIES
    " will select the entire table if a row with all initial fields is passed.
    " Use an explicit loop instead of FILTER to avoid runtime requirements
    " for specific table keys on the incoming `keys` table.
    DATA lt_keys_non_initial LIKE keys.
    LOOP AT keys INTO DATA(ls_key_row).
      IF ls_key_row-uuid IS NOT INITIAL.
        APPEND ls_key_row TO lt_keys_non_initial.
      ENDIF.
    ENDLOOP.

    IF lt_keys_non_initial IS INITIAL.
      " No valid keys to read
      CLEAR result.
      RETURN.
    ENDIF.

    SELECT *
      FROM YVEND_CONTRACT
      FOR ALL ENTRIES IN @lt_keys_non_initial
      WHERE uuid = @lt_keys_non_initial-uuid
      INTO TABLE @DATA(lt_contracts).

    result = CORRESPONDING #( lt_contracts ).
  ENDMETHOD.

  " Lock semantics: validate that each requested key still exists in the
  " active table. If not found, report a failure so the caller can handle
  " the missing entity appropriately.
  "
  " Parameters:
  " - keys: keys to lock
  " - failed-vendor_contract: output table populated with keys that failed
  " - reported-vendor_contract: output table populated with messages for
  "   each failed key (used by RAP to show errors to the user)
  METHOD lock.
    LOOP AT keys INTO DATA(ls_key).
        SELECT SINGLE uuid
          FROM YVEND_CONTRACT
        WHERE uuid = @ls_key-uuid
        INTO @DATA(lv_uuid).

      IF sy-subrc <> 0.
        APPEND VALUE #( uuid = ls_key-uuid ) TO failed-vendor_contract.
        APPEND VALUE #( uuid = ls_key-uuid
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text = 'Vendor contract does not exist anymore.' ) )
          TO reported-vendor_contract.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " Action handler for `approve`. Performs a local-mode MODIFY to change
  " status to 'APPROVED' and returns the updated entities to the caller.
  "
  " Parameters:
  " - keys: key rows indicating which instances to approve
  " - result: populated with the updated entities (wrapped in %param)
  METHOD approve.
    MODIFY ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'APPROVED' ) ).

    READ ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    result = VALUE #( FOR ls_contract IN lt_contracts
                      ( %tky = ls_contract-%tky
                        %param = ls_contract ) ).
  ENDMETHOD.

  " Action handler for `reject`. Sets status to 'REJECTED' for the
  " provided keys and returns the updated entities.
  "
  " Parameters:
  " - keys: key rows indicating which instances to reject
  " - result: populated with the updated entities (wrapped in %param)
  METHOD reject.
    MODIFY ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'REJECTED' ) ).

    READ ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    result = VALUE #( FOR ls_contract IN lt_contracts
                      ( %tky = ls_contract-%tky
                        %param = ls_contract ) ).
  ENDMETHOD.

  " Action handler for `submit`. Sets status to 'SUBMITTED' for the
  " provided keys and returns the updated entities.
  "
  " Parameters:
  " - keys: key rows indicating which instances to submit
  " - result: populated with the updated entities (wrapped in %param)
  METHOD submit.
    MODIFY ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    UPDATE FIELDS ( status )
    WITH VALUE #( FOR key IN keys ( %tky   = key-%tky
                                    status = 'SUBMITTED' ) ).

    READ ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    result = VALUE #( FOR ls_contract IN lt_contracts
                      ( %tky = ls_contract-%tky
                        %param = ls_contract ) ).
  ENDMETHOD.

  " Determination handler for renewal flag. In the unmanaged scenario the
  " flag is calculated eagerly during create/update and therefore this
  " method intentionally remains empty to avoid duplicate MODIFY calls.
  "
  " Example: when end_date is within 30 days of today, the renewal_required
  " flag is set to abap_true during create/update. This avoids invoking
  " an additional MODIFY during determination phase which could create
  " duplicate change-buffer entries.
  METHOD calculateRenewalFlag.
    " In unmanaged scenario, renewal_required is already calculated in the create method.
    " This determination intentionally does not perform MODIFY to avoid
    " duplicate create operations in the change buffer.
    " The renewal flag is updated directly on field changes in the buffer.
  ENDMETHOD.

  " Determination handler to set initial status defaults. For unmanaged
  " scenario defaulting is performed in the create method, so this is a
  " noop to avoid duplicate changes in the buffer.
  "
  " Example: a new contract without status will have status 'DRAFT' set
  " during create; this method is intentionally empty to avoid creating
  " an extra change entry during determination.
  METHOD setInitialDefaultStatus.
    " In unmanaged scenario, status is already set to 'DRAFT' in the create method.
    " This determination intentionally does not perform MODIFY to avoid
    " duplicate create operations in the change buffer.
  ENDMETHOD.

  " Validation executed on save: ensures contract_value is positive. Any
  " failed rows are added to failed-vendor_contract and reported with a
  " domain-specific message id/number.
  "
  " Parameters/outputs:
  " - keys: key rows indicating which instances to validate
  " - failed-vendor_contract: table populated with keys for which validation
  "   failed
  " - reported-vendor_contract: table populated with error messages and
  "   element indications so the UI can highlight offending fields
  METHOD validateAmount.
    READ ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( contract_value )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    IF lt_contracts IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_contracts INTO DATA(ls_contract).
      IF ls_contract-contract_value LE 0.
        APPEND VALUE #( %tky = ls_contract-%tky ) TO failed-vendor_contract.
        APPEND VALUE #( %tky = ls_contract-%tky
                        %msg = new_message( id       = 'ZMC_VENDOR_CONTRACT'
                                            number   = '002'
                                            severity = if_abap_behv_message=>severity-error )
                        %element-contract_value = if_abap_behv=>mk-on )
          TO reported-vendor_contract.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  " Validation executed on save: ensures end_date is not before start_date.
  " Validation failures are added to failed-vendor_contract and reported.
  "
  " Parameters/outputs:
  " - keys: key rows indicating which instances to validate
  " - failed-vendor_contract: table populated with keys for which validation
  "   failed
  " - reported-vendor_contract: table populated with error messages and
  "   element indications so the UI can highlight offending fields
  METHOD validateDates.
    READ ENTITIES OF yi_vendor_contract_um IN LOCAL MODE
    ENTITY vendor_contract
    FIELDS ( start_date end_date )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_contracts).

    IF lt_contracts IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_contracts INTO DATA(ls_contract).
      IF ls_contract-end_date < ls_contract-start_date.
        APPEND VALUE #( %tky = ls_contract-%tky ) TO failed-vendor_contract.
        APPEND VALUE #( %tky = ls_contract-%tky
                        %msg = new_message( id       = 'ZMC_VENDOR_CONTRACT'
                                            number   = '001'
                                            severity = if_abap_behv_message=>severity-error )
                        %element-end_date = if_abap_behv=>mk-on )
          TO reported-vendor_contract.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

CLASS lsc_YI_VENDOR_CONTRACT_UM DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.

    METHODS finalize REDEFINITION.

    METHODS check_before_save REDEFINITION.

    METHODS save REDEFINITION.

    METHODS cleanup REDEFINITION.

    METHODS cleanup_finalize REDEFINITION.

ENDCLASS.

CLASS lsc_YI_VENDOR_CONTRACT_UM IMPLEMENTATION.

  METHOD finalize.
    " Finalize stays lightweight; database persistence is centralized in
    " `save` so draft activation reaches the active table only once.
  ENDMETHOD.

  METHOD check_before_save.
    " Save-time business validations are implemented in the handler methods
    " `validateDates` and `validateAmount`, which the RAP runtime calls
    " before the saver lifecycle reaches the final database commit.
  ENDMETHOD.

  METHOD save.
    " Persist buffered changes into the active table. Wrap DB operations
    " in TRY...CATCH so runtime exceptions are handled and can be surfaced
    " in a controlled way rather than causing an unchecked short dump.
    TRY.
      LOOP AT lcl_contract_buffer=>gt_delete INTO DATA(lv_uuid).
        DELETE FROM YVEND_CONTRACT
          WHERE uuid = @lv_uuid.
      ENDLOOP.

      IF lcl_contract_buffer=>gt_create IS NOT INITIAL.
        INSERT YVEND_CONTRACT FROM TABLE @lcl_contract_buffer=>gt_create.
      ENDIF.

      IF lcl_contract_buffer=>gt_update IS NOT INITIAL.
        UPDATE YVEND_CONTRACT FROM TABLE @lcl_contract_buffer=>gt_update.
      ENDIF.
    CATCH cx_root INTO DATA(lx).
      " Re-raise so the RAP runtime gets a clear exception and the dump
      " contains the original exception information. This avoids
      " uncontrolled short dumps and makes root cause analysis easier.
      RAISE EXCEPTION lx.
    ENDTRY.
  ENDMETHOD.

  METHOD cleanup.
    lcl_contract_buffer=>reset( ).
  ENDMETHOD.

  METHOD cleanup_finalize.
    lcl_contract_buffer=>reset( ).
  ENDMETHOD.

ENDCLASS.
