/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeDetailIns]
	@GroupMinFeeId				SMALLINT,
	@GroupMinFeeSettingData		VARCHAR(MAX),
	@ErrCode					INT				= 0		OUTPUT,
	@ErrMsg						VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200630@Happy
	Task : Insert new GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:

	Param's Explannation: 
						@GroupMinFeeSettingData = '<Root>
							<GroupMinFeeSetting>
								<ProductId>0</ProductId>
								<MinimumFee>5000</MinimumFee>
								<MinimumFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinimumFeeTerm>
								<CurrencyId>6</CurrencyId>
								<FromDate>20190108</FromDate>
								<ToDate>20500101</ToDate>
							</GroupMinFeeSetting>
							<GroupMinFeeSetting>
								<ProductId>0</ProductId>
								<MinimumFee>2</MinimumFee>
								<MinimumFeeTerm></MinimumFeeTerm>
								<CurrencyId>6</CurrencyId>
								<FromDate>20190108</FromDate>
								<ToDate>20190407</ToDate>
							</GroupMinFeeSetting>
						</Root>'
*/
BEGIN
	SET NOCOUNT ON;
	
	IF ISNULL(@GroupMinFeeSettingData, '') = '' RETURN
	
	DECLARE @GroupMinFeeSettings TABLE(Idx INT IDENTITY(1, 1), ProductId INT, CurrencyId INT, FromDate DATE, ToDate DATE, MinimumFee MONEY, MinimumFeeTerm NVARCHAR(500))
	DECLARE @docHandler INT
	
	BEGIN TRY
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @GroupMinFeeSettingData
		INSERT INTO @GroupMinFeeSettings(ProductId, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
		SELECT ProductId, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm
		FROM OPENXML(@docHandler, 'Root/GroupMinFeeSetting')
		WITH(ProductId INT 'ProductId',
				CurrencyId INT 'CurrencyId',
				FromDate DATE 'FromDate',
				ToDate DATE 'ToDate',
				MinimumFee MONEY 'MinFee',
				MinimumFeeTerm NVARCHAR(500) 'MinimumFeeTerm')
				
		EXEC sp_xml_removedocument @docHandler
	END TRY
	BEGIN CATCH
		SELECT @ErrMsg = 'Group Min Fee setting data invalid. Please try again.', @ErrCode = 100
		RETURN
	END CATCH
	
	--FromDate must less than ToDate
	IF EXISTS (SELECT TOP 1 1 FROM @GroupMinFeeSettings WHERE FromDate > ToDate)
	BEGIN
		SELECT @ErrMsg = 'From Date could not be later than To Date', @ErrCode = 506
		RETURN
	END
	
	--Duplicated from date/ to date between settings
	IF EXISTS (
		SELECT TOP 1 1
		FROM @GroupMinFeeSettings a 
			LEFT JOIN @GroupMinFeeSettings b ON a.Idx <> b.Idx AND a.ProductId = b.ProductId AND a.CurrencyId = b.CurrencyId
		WHERE(a.FromDate <= b.ToDate AND a.ToDate >= B.FromDate))
	BEGIN
		SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 506
		RETURN
	END
	
	--Check setting time exceeds master time range
	DECLARE @HeaderFromDate DATE,
			@HeaderToDate DATE
			
	SELECT @HeaderFromDate = FromDate, @HeaderToDate = ToDate 
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK) 
	WHERE GroupMinFeeID = @GroupMinFeeId
	
	IF EXISTS (
		SELECT TOP 1 1
		FROM @GroupMinFeeSettings WHERE (FromDate < @HeaderFromDate OR ToDate > @HeaderToDate))
	BEGIN
		SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 506
		RETURN
	END
	
	INSERT INTO dbo.LA_GroupMinFeeDetail(GroupMinFeeID, ProductID, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
	SELECT @GroupMinFeeId, ProductId, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm
	FROM @GroupMinFeeSettings
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert LA_GroupMinFeeDetail failed. Please try again.', @ErrCode = 503
		RETURN
	END
END
GO
