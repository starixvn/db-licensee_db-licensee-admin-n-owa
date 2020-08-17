/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeUpd_RollBack]
	@GroupMinFeeID				SMALLINT,
	@GroupMinFeeHeaderOldData	XML,
	@LicenseeSettingOldData		XML,
	@GroupMinFeeSettingOldData	XML,
	@ErrCode					INT				= 0		OUTPUT,
	@ErrMsg						VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200703@Happy
	Task : Update GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20200703@Happy: Implement Group Min Fee [#134492]

	Param's Explannation:
		@GroupMinFeeHeaderOldData = '<Root>
										<GroupMinFeeHeader>
											<GroupMinFeeID>1</GroupMinFeeID>
											<Name>Group_1</Name>
											<FromDate>20190108</FromDate>
											<ToDate>20500101</ToDate>
										</GroupMinFeeHeader>
									</Root>'
									
		@LicenseeSettingData = '<Root>
									<LicenseeSetting>
										<PartyID>1</PartyID>
										<IsPrimary>1</IsPrimary>
									</LicenseeSetting>
									<LicenseeSetting>
										<PartyID>2</PartyID>
										<IsPrimary>0</IsPrimary>
									</LicenseeSetting>
								</Root>'
		
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
	DECLARE @docHandler INT
	--#Region LA_GroupMinFeeHeader
	IF (@GroupMinFeeHeaderOldData IS NOT NULL AND @GroupMinFeeHeaderOldData.exist('*') <> 0)
	BEGIN
		DECLARE @HeaderTable TABLE (GroupMinFeeID SMALLINT, Name NVARCHAR(110), FromDate DATE, ToDate DATE)

		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @GroupMinFeeHeaderOldData
			INSERT INTO @HeaderTable(GroupMinFeeID, Name, FromDate, ToDate)
			SELECT GroupMinFeeID, Name, FromDate, ToDate
			FROM OPENXML(@docHandler, 'Root/GroupMinFeeHeader')
			WITH(GroupMinFeeID SMALLINT 'GroupMinFeeID',
					Name NVARCHAR(110) 'Name', 
					FromDate DATE 'FromDate', 
					ToDate DATE 'ToDate')
				
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Header backup data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH;

		UPDATE t WITH(ROWLOCK, UPDLOCK)
		SET t.Name = s.Name, t.FromDate = s.FromDate, t.ToDate = s.ToDate
		FROM dbo.LA_GroupMinFeeHeader t
		INNER JOIN @HeaderTable s ON t.GroupMinFeeID = s.GroupMinFeeID
	END
	--#Endregion
	
	--#Region LA_GroupMinFeeAssignment
	IF(@LicenseeSettingOldData IS NOT NULL AND @LicenseeSettingOldData.exist('*') <> 0)
	BEGIN
		DECLARE @LicenseeSettingTable TABLE (PartyID INT, IsPrimary BIT)
		
		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @LicenseeSettingOldData
			INSERT INTO @LicenseeSettingTable(PartyID, IsPrimary)
			SELECT PartyID, IsPrimary
			FROM OPENXML(@docHandler, 'Root/LicenseeSetting')
			WITH(PartyID INT 'PartyID',
					IsPrimary BIT 'IsPrimary')
				
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Licensee setting backup data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH;
		
		DELETE 
		FROM dbo.LA_GroupMinFeeAssignment WITH(ROWLOCK)
		WHERE GroupMinFeeID = @GroupMinFeeID
		
		INSERT INTO LA_GroupMinFeeAssignment(GroupMinFeeID, PartyID, IsPrimary)
		SELECT @GroupMinFeeID, PartyID, IsPrimary
		FROM @LicenseeSettingTable
	END
	--#Endregion
	
	--#Region LA_GroupMinFeeDetail
	IF(@GroupMinFeeSettingOldData IS NOT NULL AND @GroupMinFeeSettingOldData.exist('*') <> 0)
	BEGIN
		DECLARE @GroupMinFeeSettingTable TABLE (ProductID INT, CurrencyId INT, FromDate DATE, ToDate DATE, MinimumFee MONEY, MinimumFeeTerm NVARCHAR(500))
		
		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @GroupMinFeeSettingOldData
			INSERT INTO @GroupMinFeeSettingTable(ProductID, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
			SELECT ProductID, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm
			FROM OPENXML(@docHandler, 'Root/GroupMinFeeSetting')
			WITH(ProductID INT 'ProductId', 
					CurrencyId INT 'CurrencyId', 
					FromDate DATE 'FromDate', 
					ToDate DATE 'ToDate', 
					MinimumFee MONEY 'MinimumFee', 
					MinimumFeeTerm NVARCHAR(500) 'MinimumFeeTerm')
				
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Group Min fee setting backup data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH;
		
		DELETE 
		FROM dbo.LA_GroupMinFeeDetail WITH(ROWLOCK)
		WHERE GroupMinFeeID = @GroupMinFeeID
		
		INSERT INTO dbo.LA_GroupMinFeeDetail(GroupMinFeeID, ProductID, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
		SELECT @GroupMinFeeID, ProductID, CurrencyId, FromDate, ToDate, MinimumFee, MinimumFeeTerm
		FROM @GroupMinFeeSettingTable
	END
	--#Endregion
END
GO
