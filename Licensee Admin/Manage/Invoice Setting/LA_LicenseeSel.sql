/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_LicenseeSel] 
	@Environment VARCHAR(50) = 'LOCAL',
	@PartyIds	 VARCHAR(MAX) = ''
AS
/*  
	 Created: 20180727@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180727@Parsons: get licensee info [#94282]
		- 20201104@Parsons: Group Min Fee & Discount Group - Enhance to check the launch date of Licensee [#144502]
		- 20231011@Danny: return LaunchedDate and the last day of previous billing cycle [#194890]
		- 20240306@Danny: get last day of previous billing cycle by Param input [#201935]

	 Params:

	 Explannation: EXEC LA_LicenseeSel
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @MaxInvoiceDate DATE
	SELECT  @MaxInvoiceDate = MAX(InvoiceDate) 
	FROM LA_InvoiceHeader WITH(NOLOCK) 
	WHERE InvoiceType = 1 AND StatusId = 0 AND Environment = @Environment
	AND ( 
			@PartyIds = ''
			OR
			PartyID IN ( SELECT CAST(value AS INT) AS PartyID FROM STRING_SPLIT(@PartyIds,',') x) 
		)

	SELECT @MaxInvoiceDate = ISNULL(@MaxInvoiceDate,'1900-01-01')

	; WITH t AS
	(
		SELECT FromParty AS PartyID, MIN(FromDate) AS AffectedDate
		FROM OAS_ChargeInfo ci WITH(NOLOCK)
		WHERE @PartyIds = '' OR FromParty IN ( SELECT CAST(value AS INT) AS PartyID FROM STRING_SPLIT(@PartyIds,',') x)
		GROUP BY FromParty
	)
	SELECT  t.PartyID, t.AffectedDate, op.LaunchDate, @MaxInvoiceDate MaxInvoiceDate
	FROM t 
	LEFT JOIN OAS_PartyDetail op WITH(NOLOCK) ON t.PartyID = op.PartyID
END
GO