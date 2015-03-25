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
	Param's Explanation:  
*/  
SET NOCOUNT ON
BEGIN
	SELECT 
		/*
		SELECT 
			GETDATE() AS FirstBilling, 
			'15% of Net Win' AS BasisOfBilling, 
			'EUR15000 (minimum fees waived 3 months from date of launch)' AS MinimumFees,  
			REPLACE(CONVERT(VARCHAR(11),GETDATE(),6), ' ', '-') AS HeadOfTerms
		*/
		'' AS FirstBilling, -- example 'Jan-01' 
		'' AS BasisOfBilling, 
		'' AS MinimumFees,  
		'' AS HeadOfTerms
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_LicenseeBillingInfoSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_LicenseeBillingInfoSel] TO bodbAdminNet