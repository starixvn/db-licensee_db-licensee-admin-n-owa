/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_BankInfoSel]
	 @BillerId	INT	= 0	
AS
/*  
	Created: 20150604@Florent
	Task : get list bank info 
	DB: DBCUST.bodb_Licensee  
   
	Revisions:
		- 20150604@Florent: Initialize SP
	
	Params:		
	Example: EXEC dbo.LA_BankInfoSel @BillerId = 1
*/
BEGIN

	SET NOCOUNT ON
	SELECT
		p.PartyID	AS BillerID
		, b.BankId
		, b.BeneficiaryName
		, b.AccountNumber
		, b.BankName
		, b.BankAddress
		, b.IBAN
		, b.SwiftCode
		, b.CorrespondentBank
		, b.CorrespondentAccountNumber
		, b.CorrespondentAddress
		, b.CorrespondentSwiftCode
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.LA_BankInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID
	WHERE p.PartyType = 4
		AND (@BillerId = 0 OR p.PartyID = @BillerId)
END
GO