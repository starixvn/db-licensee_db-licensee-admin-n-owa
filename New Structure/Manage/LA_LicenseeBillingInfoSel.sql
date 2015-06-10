USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_LicenseeBillingInfoSel]
	@PartyId			TINYINT
	, @ProductCode		VARCHAR(6)
AS
/*  Created: 20150318@Florent	
	Task : Report - Licensee Settlement Report
	Base on : IMS_LicenseeBillingInfoSel
	DB: DBLIC.bodb_Licensee
	Revisions:  
		- 201505628@Florent: implement code
	Param's Explanation:  
*/  
BEGIN
	SET NOCOUNT ON
	DECLARE @FirstBilling VARCHAR(6)
		, @BasisOfBilling VARCHAR(50)
		, @MinimumFees VARCHAR(10)
	SELECT 	
		@FirstBilling =  CONVERT(VARCHAR(3),DATENAME(MONTH, DATEADD(MONTH, MONTH(ci.FirstOfBilling), - 1))) + '-' + SUBSTRING(CAST(YEAR(ci.FirstOfBilling) AS VARCHAR),3,2)
		, @BasisOfBilling = ISNULL(BasicOfBilling, '')
		, @MinimumFees = ISNULL(m.MinFeeTerm, '')	
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2	
		INNER JOIN (SELECT MAX(c.FromDate) FromDate, c.FromParty, c.ProductID FROM dbo.OAS_ChargeInfo c WITH (NOLOCK)
								INNER JOIN dbo.LA_ChargeInfo_SystemMapping csm WITH (NOLOCK) ON c.ChargeID = csm.ChargeID AND csm.SystemID = 2
								INNER JOIN (SELECT ProductPrefix, ProductID FROM dbo.LA_f_Products3rd(@ProductCode)) pp ON c.ProductID = pp.ProductID
							WHERE c.FromParty = @PartyId
								AND c.ChargeType = 1
							GROUP BY c.FromParty, c.ProductID) t ON ci.FromDate = t.FromDate AND ci.FromParty = t.FromParty AND ci.ProductID = t.ProductID
		LEFT JOIN (SELECT FromDate, ToDate, PartyId, ProductId, MinFeeTerm
					FROM dbo.LA_MinFee  WITH (NOLOCK) 
					WHERE CONVERT(DATE, GETDATE()) BETWEEN FromDate AND ToDate
					AND PartyId = @PartyId) m ON ci.FromParty = m.PartyId AND ci.ProductID = m.ProductId 
	WHERE ci.FromParty = @PartyId	
		AND ci.ChargeType = 1
		
	SELECT  ISNULL(@FirstBilling, '')		AS FirstBilling
			, ISNULL(@BasisOfBilling, '')	AS BasisOfBilling
			, ISNULL(@MinimumFees, '')		AS MinimumFees
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_LicenseeBillingInfoSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_LicenseeBillingInfoSel] TO bodbAdminNet