CLASS zcl_vc_status_cr2 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_sadl_exit .
    INTERFACES if_sadl_exit_calc_element_read .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_vc_status_cr2 IMPLEMENTATION.


  METHOD if_sadl_exit_calc_element_read~calculate.

    FIELD-SYMBOLS:
      <ls_original> TYPE any,
      <ls_calc>     TYPE any,
      <lv_status>   TYPE any,
      <lv_crit>     TYPE any.

    LOOP AT it_original_data ASSIGNING <ls_original>.
      ASSIGN ct_calculated_data[ sy-tabix ] TO <ls_calc>.

      ASSIGN COMPONENT 'STATUS'
        OF STRUCTURE <ls_original>
        TO <lv_status>.

      ASSIGN COMPONENT 'STATUS_CRITICALITY'
        OF STRUCTURE <ls_calc>
        TO <lv_crit>.

      IF <lv_status> IS ASSIGNED
         AND <lv_crit> IS ASSIGNED.

        CASE <lv_status>.

          WHEN 'REJECTED'.
            <lv_crit> = 1.

          WHEN 'SUBMITTED'.
            <lv_crit> = 2.

          WHEN 'APPROVED'.
            <lv_crit> = 3.

          WHEN OTHERS.
            <lv_crit> = 0.

        ENDCASE.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  METHOD if_sadl_exit_calc_element_read~get_calculation_info.
  ENDMETHOD.
ENDCLASS.
