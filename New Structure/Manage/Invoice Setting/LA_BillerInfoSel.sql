USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_BillerInfoSel]
	 @BillerId	INT	= 0	
AS
/*  
	 Created: 20150413@Florent
	 Task : get Biller Information by Id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
	 Example:
		EXEC dbo.LA_BillerInfoSel 125
*/
SET NOCOUNT ON
BEGIN
	SELECT b.PartyID AS BillerID
		, b.BillerName
		, b.StatusId
		, b.BillerFullName
		, b.CompanyName
		, b.Address1
		, b.Address2
		, b.LogoPath
		, b.Description
		, b.BeneficiaryName
		, b.AccountNumber
		, b.BankName
		, b.BankAddess
		, b.IBAN
		, b.SwiftCode
		, b.CorrespondentBank
		, b.CorrespondentAccountNumber
		, b.CorrespondentAddress
		, b.CorrespondentSwiftCode
	FROM dbo.OAS_Party p WITH (NOLOCK)
	INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID
	WHERE p.PartyType = 4
		AND p.PartyID = @BillerId
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_BillerInfoSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_BillerInfoSel] TO bodbAdminNet 