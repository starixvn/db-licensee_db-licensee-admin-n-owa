/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Inv_BankInfoGet] 
	  @BillerId INT
	, @PayerId INT	
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DBCUST.bodb_Licensee
   
	Revisions: 
		- 20150806@Bravo: Bank Info - Get
*/
/*	Example:
	use bodb_licensee
	DECLARE @BillerId INT = 98
	DECLARE @PayerId INT = 15
	EXEC [LA_Inv_BankInfoGet] @BillerId, @PayerId
*/
BEGIN		
	SET NOCOUNT ON
	
	SELECT TOP 1 
			b.BankId,
			b.AccountNumber,
			b.BankName,
			b.BankAddress,
			b.IBAN,
			b.BeneficiaryName,
			b.SwiftCode,
			b.CorrespondentBank,
			b.CorrespondentAccountNumber,
			b.CorrespondentAddress,
			b.CorrespondentSwiftCode
	FROM	dbo.LA_InvoiceSetting s WITH(NOLOCK) 
			INNER JOIN dbo.LA_BankInfo b WITH(NOLOCK) ON s.ToPartyId = b.PartyId AND s.BankId = b.BankId
	WHERE	s.ToPartyId = @BillerId 
			AND s.FromPartyId = @PayerId
		
END
GO