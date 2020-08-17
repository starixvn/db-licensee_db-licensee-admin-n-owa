/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeDetailUpd]
	@GroupMinFeeID				SMALLINT,
	@GroupMinFeeSettingData		VARCHAR(MAX),
	@OldData					XML				= ''	OUTPUT,
	@ErrCode					INT				= 0		OUTPUT,
	@ErrMsg						VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200701@Happy
	Task : Update GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20200701@Happy: Implement Group Min Fee [#134492]

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
								<MinimumFeeTerm />
								<CurrencyId>6</CurrencyId>
								<FromDate>20190108</FromDate>
								<ToDate>20190407</ToDate>
							</GroupMinFeeSetting>
						</Root>'
*/
BEGIN
	SET NOCOUNT ON;
	
	IF ISNULL(@GroupMinFeeSettingData, '') = '' RETURN
	
	DECLARE @GroupMinFeeSettings TABLE(Idx INT IDENTITY(1, 1), GroupMinFeeID SMALLINT, ProductId INT, CurrencyId INT, FromDate DATE, ToDate DATE, MinimumFee MONEY, MinimumFeeTerm NVARCHAR(500))
	DECLARE @docHandler INT
	
	BEGIN TRY
		EXEC sp_xml_preparedocument @docHandler OUTPUT, @GroupMinFeeSettingData
		INSERT INTO @GroupMinFeeSettings(GroupMinFeeID, ProductId, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
		SELECT @GroupMinFeeID, ProductId, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm
		FROM OPENXML(@docHandler, 'Root/GroupMinFeeSetting')
		WITH(ProductId INT 'ProductId',
				CurrencyId INT 'CurrencyId',
				FromDate DATE 'FromDate',
				ToDate DATE 'ToDate',
				MinimumFee MONEY 'MinimumFee',
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
	
	--#Region backup
	SET @OldData = (
		SELECT GroupMinFeeID, ProductID, CurrencyID, FromDate, ToDate, MinimumFee, MinimumFeeTerm
		FROM dbo.LA_GroupMinFeeDetail WITH(NOLOCK)
		WHERE GroupMinFeeID = @GroupMinFeeID FOR XML PATH('GroupMinFeeSetting'), ROOT('Root'))
	--#Endregion
	
	--#Region update
	;MERGE dbo.LA_GroupMinFeeDetail WITH(ROWLOCK, UPDLOCK) AS t
	USING @GroupMinFeeSettings AS s
	ON(t.GroupMinFeeID = s.GroupMinFeeID AND t.ProductID = s.ProductID AND t.CurrencyID = s.CurrencyID AND t.FromDate = s.FromDate)
	WHEN MATCHED
		THEN UPDATE SET t.FromDate = s.FromDate, 
						t.ToDate = s.ToDate, 
						t.MinimumFee = s.MinimumFee, 
						t.MinimumFeeTerm = s.MinimumFeeTerm
	WHEN NOT MATCHED BY TARGET
		THEN INSERT(GroupMinFeeID, ProductID, CurrencyID, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
				VALUES(s.GroupMinFeeID, s.ProductID, s.CurrencyID, s.FromDate, s.ToDate, s.MinimumFee, s.MinimumFeeTerm)
	WHEN NOT MATCHED BY SOURCE AND t.GroupMinFeeID = @GroupMinFeeID
		THEN DELETE;
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update LA_GroupMinFeeDetail failed. Please try again.', @ErrCode = 503
		RETURN
	END
END
GO
