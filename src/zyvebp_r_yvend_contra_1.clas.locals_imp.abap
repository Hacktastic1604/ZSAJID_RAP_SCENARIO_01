CLASS lhc_zyver_yvend_contra_1 DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR ZyverYvendContra1
        RESULT result.
ENDCLASS.

CLASS lhc_zyver_yvend_contra_1 IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
ENDCLASS.
