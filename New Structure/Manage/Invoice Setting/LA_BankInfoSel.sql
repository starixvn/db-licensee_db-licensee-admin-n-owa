USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BankInfoSel]
	 @BillerId	INT	= 0	
AS
/*  
	 Created: 20150604@Florent
	 Task : get list bank info 
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:		
	 Example:
		EXEC dbo.LA_BankInfoSel 1
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
GRANT VIEW DEFINITION ON [dbo].[LA_BankInfoSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BankInfoSel] TO bodbAdminNet 