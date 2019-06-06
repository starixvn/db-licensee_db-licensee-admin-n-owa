/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesPayerSettingsSel]
	@PayerId INT
AS
/*
	Created: 201600708@Bruce
	Task : Get all hosting fees settings of payer
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 201600708@Bruce: create
	
	Params:

	Example:
		EXEC dbo.LA_HostingFeesPayerSettingsSel 14
*/
BEGIN	
	SET NOCOUNT ON

	DECLARE @ProductName VARCHAR(50) = 'Hosting'
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)
	DECLARE @LastDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)

	-- Base currency
	SELECT PartyID AS PayerId, BaseCurrencyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE PartyID = @PayerId

	-- Minfee product list
	SELECT DISTINCT m.ProductId, p.ProductName
	FROM dbo.LA_MinFee m WITH (NOLOCK)
	LEFT JOIN dbo.LA_f_Products3rd('') p ON m.ProductID = p.ProductID
	WHERE m.PartyId = @PayerId and m.FeeTypeId = 1

	-- Settings info
	SELECT
		s.ChargeId,
		s.FromParty AS PayerId,
		s.ProductName,
		s.FirstBilling,
		s.BasisOfBilling,
		s.HostingFeesId,
		f.HostingFeesName,
		t.HostingFeesTypeName,
		s.FromDate,
		s.ToDate,
		s.BasedMinimunFees AS BasedMinimunFeesId,
		pr.ProductName AS BasedMinimunFeesName,
		s.SettingType
	FROM dbo.LA_HostingFeesSetting s WITH (NOLOCK)
		LEFT JOIN dbo.LA_f_Products3rd('') pr ON s.BasedMinimunFees = pr.ProductID
		LEFT JOIN dbo.LA_HostingFees f WITH (NOLOCK) ON s.HostingFeesId = f.HostingFeesId
		LEFT JOIN dbo.LA_HostingFeesTypes t WITH (NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
	WHERE s.FromParty = @PayerId
	ORDER BY s.SettingType, s.FromDate
END
GO