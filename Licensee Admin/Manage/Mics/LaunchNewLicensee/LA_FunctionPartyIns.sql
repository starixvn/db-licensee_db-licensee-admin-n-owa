/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_FunctionPartyIns] 
	@FunctionKey	NVARCHAR(100), 
	@PartyId		INT	
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190107@Parsons: Launch new licensee

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FunctionID INT

	SELECT @FunctionID = FunctionID 
	FROM dbo.LA_Function WITH (NOLOCK) 
	WHERE FunctionKey = @FunctionKey
			
	IF ISNULL(@FunctionID,0) = 0 OR ISNULL(@PartyID,0) = 0		
	BEGIN
		SELECT 'Error!!! Data error, please check :', @FunctionKey AS '@FunctionKey', @FunctionID AS '@FunctionID', @PartyID AS '@PartyID'
		RETURN
	END

	IF NOT EXISTS (SELECT 1 FROM dbo.LA_FunctionParty WITH (NOLOCK) WHERE FunctionID = @FunctionID AND PartyID = @PartyID)
	BEGIN
		INSERT INTO dbo.LA_FunctionParty (FunctionID, PartyID)
		VALUES(@FunctionID, @PartyID)
	END
	ELSE 
	BEGIN	
		SELECT 'Error!!! Permission exists, please check :', @FunctionKey AS '@FunctionKey', @FunctionID AS '@FunctionID', @PartyID AS '@PartyID'
	END
END
GO