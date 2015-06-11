USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_PayerListSel]
	 @PayerId	INT	= 0	
AS
/*  
	 Created: 20150414@Florent
	 Task : get List Payer by all or by Id
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all payer
		+ <> 0 specify a payer
	 Example:
		EXEC dbo.LA_PayerListSel 0
*/
BEGIN	
	SET NOCOUNT ON
	;WITH cte_BillerPayer(FromPartyId, ToPartyID)
	AS 
	(
		SELECT FromPartyId, ToPartyID 
		FROM dbo.LA_InvoiceSetting WITH (NOLOCK)
		GROUP BY FromPartyId, ToPartyID 	
	)
	SELECT p.PartyID		AS PayerID
		, p.PartyName		AS PayerName
		, pd.BrandName
		, pd.CompanyName
		, COUNT(i.ToPartyId) AS NumberOfBillers	
		, STUFF((
				SELECT ', ' + CAST(b.BillerName AS VARCHAR)
				FROM cte_BillerPayer ii
					LEFT JOIN dbo.LA_BillerInfo b ON ii.ToPartyId = b.PartyId
				WHERE b.PartyID = ii.ToPartyID		
					AND ii.FromPartyId = p.PartyID			
				FOR XML PATH (''))
			  , 1, 2, '') AS BillerList		
		, pd.StatusId 
	FROM dbo.OAS_Party p WITH (NOLOCK)		
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN cte_BillerPayer i ON i.FromPartyId = p.PartyID
	WHERE p.PartyType = 1
		AND (@PayerId = 0 OR p.PartyID = @PayerId)
	GROUP BY p.PartyID, p.PartyName, pd.BrandName, pd.CompanyName, pd.StatusId

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerListSel] TO bodbAdminNet 

