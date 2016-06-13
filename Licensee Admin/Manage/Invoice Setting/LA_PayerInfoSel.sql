USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerInfoSel]
	 @PayerId	INT	= 0,
	 @BillerId	INT = 0,
	 @InvoiceTypeId INT = 0
AS
/*  
	 Created: 20150414@Florent
	 Task : get Payer Information by Id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
	 Example:
		EXEC dbo.LA_PayerInfoSel 14
*/
BEGIN
SET NOCOUNT ON
	SELECT p.PartyID	AS PayerID
		, p.PartyName 	AS PayerName
		, pd.StatusId
		, pd.IsDeposit
		, pd.BrandName
		, pd.CompanyName
		, pd.AttnName
		, pd.Description
		, pd.Address1
		, pd.Address2	
		, i.ActiveAddress	
	FROM dbo.OAS_Party p WITH (NOLOCK)
		LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		INNER JOIN (
				SELECT i.FromPartyId, i.ToPartyId, i.InvTypeId, ActiveAddress
				FROM dbo.LA_InvoiceSetting i
				WHERE (@BillerId = 0 OR i.ToPartyId = @BillerId) AND (@InvoiceTypeId = 0 OR InvTypeId = @InvoiceTypeId)
				GROUP BY i.FromPartyId, i.ToPartyId, i.InvTypeId, i.ActiveAddress
			) i ON p.PartyID = i.FromPartyId
	WHERE (@PayerId = 0 OR p.PartyID = @PayerId)
		AND p.PartyType = 1
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerInfoSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerInfoSel] TO bodbAdminNet 
