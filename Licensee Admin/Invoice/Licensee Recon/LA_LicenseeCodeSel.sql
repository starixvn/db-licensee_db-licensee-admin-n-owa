/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE [dbo].LA_LicenseeCodeSel
/*  
	Created: 20190725@Bruce
	Task : Get licensee code list for Licensee Reconciliation
	DB: DBLIC.bodb_licensee
	
	Revisions:
		- 20190725@Bruce: create SP

*/
AS
BEGIN
	SET NOCOUNT ON;

	SELECT d.PartyId, d.LicenseeCode
	FROM dbo.OAS_PartyDetail d WITH(NOLOCK)
	WHERE d.IsDeposit = 1 AND d.LicenseeCode IS NOT NULL
END