USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_BankInfoGet]   Script Date: 07/29/2015 16:33:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_BankInfoGet] 
	  @BillerId INT
	, @PayerId INT	
AS
SET NOCOUNT ON
BEGIN		
	SELECT TOP 1 b.BankId,b.AccountNumber,b.BankName,b.BankAddress,b.IBAN,b.BeneficiaryName,b.SwiftCode,b.CorrespondentBank,b.CorrespondentAccountNumber,b.CorrespondentAddress,b.CorrespondentSwiftCode
	FROM dbo.LA_InvoiceSetting s WITH(NOLOCK) INNER JOIN dbo.LA_BankInfo b WITH(NOLOCK) ON s.FromPartyId = b.PartyId AND s.BankId = b.BankId
	WHERE s.ToPartyId = @BillerId 
		AND s.FromPartyId = @PayerId
END